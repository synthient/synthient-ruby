# frozen_string_literal: true

# Prints what Synthient knows about an IP address. Each lookup costs one credit.
#
#   SYNTHIENT_API_KEY=... bundle exec ruby examples/lookup_ip.rb 8.8.8.8

require "synthient"

abort "usage: lookup_ip.rb <ip>" unless ARGV.size == 1

client = Synthient::Client.new
begin
  info = client.lookup_ip(ARGV[0])
rescue Synthient::APIError => e
  abort "out of lookup credits" if e.status == 402
  raise
ensure
  client.close
end

puts "ip: #{info.ip}"
network = info.network
puts "network: #{network.isp} (AS#{network.asn}, #{network.type})" if network
location = info.location
puts "location: #{location.city}, #{location.country}" if location
intelligence = info.intelligence
abort "no intelligence available" unless intelligence

puts "risk score: #{intelligence.risk_score}"
puts "categories: #{intelligence.categories.join(", ")}"
intelligence.providers.each do |provider|
  puts "provider: #{provider.name} (#{provider.type}), last seen #{provider.last_seen.strftime("%F %T")}"
end
