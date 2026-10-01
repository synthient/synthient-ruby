#!/usr/bin/env bash
# Builds the gem and checks what consumers receive: the packaged files, a
# plain Ruby consumer and a Bundler consumer running from an isolated
# GEM_HOME outside the checkout, the grpcschema LoadError and the working
# module once grpc is installed, and Steep against the installed signatures.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$work"' EXIT

unset RUBYLIB RUBYOPT BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_WITH BUNDLE_APP_CONFIG
export GEM_HOME="$work/gems" GEM_PATH="$work/gems" BUNDLE_USER_HOME="$work/bundle-home"
export PATH="$GEM_HOME/bin:$PATH"

cd "$root"
version="$(ruby -Ilib -e 'require "synthient/version"; print Synthient::VERSION')"
gem build --strict synthient.gemspec --output "$work/synthient-$version.gem"

files="$(gem spec "$work/synthient-$version.gem" files)"
for expected in lib/synthient.rb lib/synthient/grpcschema.rb sig/synthient.rbs sig/synthient/models.rbs sig/manifest.yaml README.md LICENSE; do
  grep -q -- "- $expected\$" <<<"$files" || { echo "missing $expected from the gem"; exit 1; }
done
if grep -qE -- "- (test|scripts|examples|vendor|\.sdkgen)/" <<<"$files"; then
  echo "the gem includes development files"
  exit 1
fi
gem spec "$work/synthient-$version.gem" dependencies | grep -qx -- "--- \[\]" || { echo "the gem has runtime dependencies"; exit 1; }

gem install --local --no-document "$work/synthient-$version.gem"

mkdir "$work/plain"
cd "$work/plain"
cat > consumer.rb <<'RUBY'
require "socket"
require "synthient"

loaded = $LOADED_FEATURES.find { |path| path.end_with?("/synthient.rb") }
abort "loaded #{loaded}, not the installed gem" unless loaded.start_with?(ENV.fetch("GEM_HOME"))

server = TCPServer.new("127.0.0.1", 0)
Thread.new do
  socket = server.accept
  nil while socket.gets != "\r\n"
  body = '{"ip":"8.8.8.8","intelligence":{"risk_score":3,"categories":[],"behavior":[],"providers":[],"devices":[]}}'
  socket.write("HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{body.bytesize}\r\n\r\n#{body}")
  socket.close
end
client = Synthient::Client.new(api_key: "key", base_url: "http://127.0.0.1:#{server.addr[1]}/api/v4")
info = client.lookup_ip("8.8.8.8")
client.close
abort "unexpected risk score" unless info.intelligence.risk_score == 3
puts "plain consumer: ok"
RUBY
ruby consumer.rb

output="$(ruby -e 'require "synthient/grpcschema"' 2>&1 || true)"
grep -q "gem install grpc google-protobuf" <<<"$output" || { echo "grpcschema did not explain its missing gems: $output"; exit 1; }
echo "grpcschema without grpc: ok"

mkdir "$work/bundler"
cd "$work/bundler"
cat > Gemfile <<RUBY
source "https://rubygems.org"
gem "synthient", "$version"
RUBY
bundle install --local --quiet
bundle exec ruby -e '
  require "synthient"
  spec = Gem.loaded_specs.fetch("synthient")
  abort "resolved #{spec.full_gem_path}" unless spec.full_gem_path.start_with?(ENV.fetch("GEM_HOME"))
  puts "bundler consumer: ok"
'

gem install --no-document grpc google-protobuf steep
cd "$work/plain"
ruby -e '
  require "synthient/grpcschema"
  abort "bad endpoint" unless Synthient::GRPCSchema.normalize_endpoint("example.com") == ["example.com:443", "example.com"]
  puts "grpcschema with grpc: ok"
'

mkdir "$work/typed"
cd "$work/typed"
cat > Steepfile <<'RUBY'
target :app do
  check "app.rb"
  library "synthient"
end
RUBY
cat > app.rb <<'RUBY'
require "synthient"

client = Synthient::Client.new(max_retries: 1, timeout: 2.5)
info = client.lookup_ip("8.8.8.8")
score = info.intelligence&.risk_score
puts score.to_s
client.lookup_ips(["1.1.1.1"]).each { |result| puts result.ip.to_s }
client.proxies.stream { |event| puts event.provider }
page = client.proxies.list_exports(limit: 10)
puts page.exports.first&.checksum
client.close
RUBY
steep check
cat > app.rb <<'RUBY'
require "synthient"

Synthient::Client.new.lookup_ip("8.8.8.8").network.asn
RUBY
if steep check >/dev/null 2>&1; then
  echo "steep accepted a nil-unsafe call, so the installed signatures were not used"
  exit 1
fi
echo "steep consumer: ok"
