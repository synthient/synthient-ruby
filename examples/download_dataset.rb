# frozen_string_literal: true

# Downloads the newest day of the Geolocation dataset as a MaxMind DB to
# geolocation.mmdb and verifies its checksum. It needs an API key with the
# GEOLOCATION_FEED scope.
#
#   SYNTHIENT_API_KEY=... bundle exec ruby examples/download_dataset.rb

require "digest"
require "synthient"

client = Synthient::Client.new
export = client.geolocation.list_exports(limit: 1).exports.first
abort "no export found" unless export
mmdb = export.formats.find { |file| file.format == Synthient::ExportFormat::MMDB }
abort "#{export.id} has no mmdb file" unless mmdb

digest = Digest::SHA256.new
File.open("geolocation.mmdb", "wb") do |file|
  client.geolocation.download(export.id, format: mmdb.format) do |chunk|
    file.write(chunk)
    digest << chunk
  end
end
client.close

abort "checksum mismatch" unless digest.hexdigest == mmdb.checksum
puts "saved #{export.id} (#{mmdb.size_bytes} bytes) to geolocation.mmdb"
