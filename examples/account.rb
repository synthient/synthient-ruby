# frozen_string_literal: true

# Prints the account that owns the API key, its scopes, and its remaining
# lookup credits. Free.
#
#   SYNTHIENT_API_KEY=... bundle exec ruby examples/account.rb

require "synthient"

client = Synthient::Client.new
account = client.account
client.close

puts "#{account.first_name} #{account.last_name} <#{account.email}>"
puts "organization: #{account.organization.name} (#{account.organization.relation})"
puts "scopes: #{account.scopes.join(", ")}"
quota = account.lookup_quota
puts "credits: #{quota.credits}, resetting in #{quota.resets_in / 3600} hours"
