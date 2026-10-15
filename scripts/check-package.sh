#!/usr/bin/env bash
# Builds the gem and checks what consumers receive: the packaged files, a
# plain Ruby consumer and a Bundler consumer running from an isolated
# GEM_HOME outside the checkout, the grpcschema LoadError and the working
# module once grpc is installed, and Steep against the installed signatures.
set -euo pipefail

root="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
cd "$root"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

unset RUBYLIB RUBYOPT RUBYGEMS_GEMDEPS $(compgen -e | grep -E '^BUNDLER?_')
export GEM_HOME="$work/gems" GEM_PATH="$work/gems" BUNDLE_USER_HOME="$work/bundle-home"
export PATH="$GEM_HOME/bin:$PATH"

gem="$work/synthient.gem"
gem build --strict synthient.gemspec --output "$gem"

diff <(gem spec "$gem" files | sed -n 's/^- //p' | sort) <(git ls-files lib sig README.md LICENSE | sort) ||
  { echo "the gem's files differ from the tracked lib, sig, README.md, and LICENSE"; exit 1; }
ruby -rrubygems/package -e 'deps = Gem::Package.new(ARGV[0]).spec.runtime_dependencies; abort "the gem has runtime dependencies: #{deps.join(", ")}" unless deps.empty?' "$gem"

gem install --local --no-document "$gem"

cd "$work"
ruby "$root/test/package/consumer.rb"
echo "plain consumer: ok"

output="$(ruby -e 'require "synthient/grpcschema"' 2>&1 || true)"
grep -q "gem install grpc google-protobuf" <<<"$output" || { echo "grpcschema did not explain its missing gems: $output"; exit 1; }
echo "grpcschema without grpc: ok"

mkdir "$work/bundler"
cd "$work/bundler"
cat > Gemfile <<'RUBY'
source "https://rubygems.org"
gem "synthient"
RUBY
bundle install --local --quiet
bundle exec ruby "$root/test/package/consumer.rb"
echo "bundler consumer: ok"

gem install --no-document grpc google-protobuf steep
ruby -e '
  require "synthient/grpcschema"
  abort "bad endpoint" unless Synthient::GRPCSchema::DEFAULT_ENDPOINT == "grpc.synthient.com:443"
  puts "grpcschema with grpc: ok"
'

mkdir "$work/typed"
cd "$work/typed"
cp -R "$root/examples" .
cat > Steepfile <<'RUBY'
target :examples do
  check "examples"
  library "synthient", "digest", "json", "time"
end
RUBY
steep check
echo 'Synthient::Client.new.lookup_ip("8.8.8.8").network.asn' > examples/nil_unsafe.rb
output="$(steep check 2>&1 || true)"
grep -q "Ruby::NoMethod" <<<"$output" || { echo "steep accepted a nil-unsafe call against the installed signatures: $output"; exit 1; }
echo "steep consumer: ok"
