# frozen_string_literal: true

# Prints the honeypot traffic Synthient has observed for a domain. Each lookup
# costs one credit.
#
#   SYNTHIENT_API_KEY=... bundle exec ruby examples/lookup_domain.rb example.com

require "synthient"

abort "usage: lookup_domain.rb <domain>" unless ARGV.size == 1

client = Synthient::Client.new
info = client.lookup_domain(ARGV[0], limit: 5)
client.close

puts "#{info.domain}: #{info.status}"
puts "events: #{info.stats.events_24h} in 24h, #{info.stats.total_events_30d} in 30d"
puts "cadence: #{info.activity_stats.cadence}"
top_asn = info.top_asn
puts "top ASN: AS#{top_asn.asn} (#{top_asn.events} events)" if top_asn
info.recent_events.each do |event|
  puts "#{event.timestamp.iso8601} #{event.source_ip} -> #{event.target_subdomain}:#{event.port} (#{event.country_code})"
end
