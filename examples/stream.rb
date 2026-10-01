# frozen_string_literal: true

# Prints proxy sightings from the real-time proxies feed until interrupted,
# reconnecting whenever the server closes the stream. It needs an API key with
# the PROXY_FIREHOSE scope.
#
#   SYNTHIENT_API_KEY=... bundle exec ruby examples/stream.rb

require "synthient"

client = Synthient::Client.new
begin
  loop do
    begin
      client.proxies.stream do |event|
        puts [event.timestamp&.iso8601 || "-", event.ip, event.provider, event.type, event.country_code].join(" ")
      end
    rescue Synthient::APIError => e
      raise if [401, 403].include?(e.status)

      warn "stream: #{e.message}"
    rescue Synthient::Error => e
      warn "stream: #{e.message}"
    end

    # The server closes each stream after about 30 minutes. Pause before
    # reconnecting so repeated failures stay under the connection rate limit.
    sleep 2
  end
rescue Interrupt
  nil
ensure
  client.close
end
