# frozen_string_literal: true

# Lists the newest exports of the proxies feed, then downloads the most recent
# daily export to proxies.parquet and verifies its checksum. It needs an API
# key with the PROXY_FEEDS scope.
#
#   SYNTHIENT_API_KEY=... bundle exec ruby examples/download_export.rb

require "digest"
require "synthient"

client = Synthient::Client.new
daily = client.proxies.each_export.find do |export|
  puts "#{export.id.ljust(16)} #{export.kind.ljust(6)} #{export.row_count.to_s.rjust(10)} rows " \
       "#{export.size_bytes.to_s.rjust(12)} bytes"
  export.kind == Synthient::ExportKind::DAILY
end
abort "no daily export found" unless daily

digest = Digest::SHA256.new
File.open("proxies.parquet", "wb") do |file|
  client.proxies.download(daily.id) do |chunk|
    file.write(chunk)
    digest << chunk
  end
end
client.close

abort "checksum mismatch" unless digest.hexdigest == daily.checksum
puts "saved #{daily.id} to proxies.parquet"
