# frozen_string_literal: true

# Looks up several IP addresses in one request and prints each risk score. The
# API drops duplicate and private addresses, so results are matched by IP.
#
#   SYNTHIENT_API_KEY=... bundle exec ruby examples/lookup_ips.rb 8.8.8.8 1.1.1.1

require "synthient"

abort "usage: lookup_ips.rb <ip>..." if ARGV.empty?

client = Synthient::Client.new
results = client.lookup_ips(ARGV)
client.close

results.each do |result|
  score = result.intelligence&.risk_score
  puts "#{result.ip}: #{score.nil? ? "no intelligence" : "risk #{score}"}"
end
