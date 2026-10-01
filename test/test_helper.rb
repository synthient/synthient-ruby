# frozen_string_literal: true

require "minitest/autorun"
require "synthient"
require_relative "support/server"

class SynthientTest < Minitest::Test
  API_KEY = "test-key"

  IP_INFO = {
    "ip" => "8.8.8.8",
    "network" => {
      "asn" => 15_169, "isp" => "Google LLC", "org" => "Google", "domain" => "google.com",
      "type" => "DATACENTER", "abuse_email" => "network-abuse@google.com", "abuse_phone" => nil
    },
    "location" => {
      "country" => "US", "state" => "California", "city" => "Mountain View", "timezone" => "America/Los_Angeles",
      "latitude" => 37.4056, "longitude" => -122.0775, "geo_hash" => "9q9hvu"
    },
    "intelligence" => {
      "risk_score" => 12,
      "categories" => ["DATACENTER"],
      "behavior" => [],
      "providers" => [{ "provider" => "BRIGHTDATA", "type" => "RESIDENTIAL_PROXY", "last_seen" => 1_778_187_600 }],
      "devices" => [{ "os" => "Android", "version" => "14", "last_seen" => 1_778_187_600 }]
    }
  }.freeze

  ACCOUNT = {
    "email" => "dev@example.com", "first_name" => "Ada", "last_name" => "Lovelace",
    "organization" => { "id" => "4f7c0a3e-0f5d-4a51-9c39-1d1f8f0f6a10", "name" => "Example", "relation" => "OWNER" },
    "scopes" => %w[BASIC PROXY_FEEDS FUTURE_SCOPE],
    "lookup_quota" => { "credits" => 9_000_000_000, "resets_in" => 86_400 },
    "api_key" => { "id" => "7d1e", "name" => "sdk", "created_at" => "2026-09-28T19:04:52.463869Z" }
  }.freeze

  EXPORT = {
    "id" => "2026-05-07/21", "kind" => "hourly", "date" => "2026-05-07", "hour" => 21, "size_bytes" => 1_048_576,
    "row_count" => 1200, "checksum" => "ab12", "created_at" => 1_778_187_600,
    "download_path" => "/api/v4/feeds/proxies/export/2026-05-07/21"
  }.freeze

  def serve(&)
    server = TestServer.new(&)
    (@servers ||= []) << server
    server
  end

  # Builds a client for a test server whose retry waits are recorded in
  # +sleeps+ instead of slept, and whose jitter is fixed at 1.0.
  def new_client(server, **)
    client = Synthient::Client.new(api_key: API_KEY, base_url: server.url, **)
    (@clients ||= []) << client
    recorded = sleeps
    transport = client.instance_variable_get(:@transport)
    transport.define_singleton_method(:sleep) { |seconds| recorded << seconds }
    transport.define_singleton_method(:rand) { 0.5 }
    client
  end

  def sleeps
    @sleeps ||= []
  end

  def json(status, body, headers = {})
    [status, { "content-type" => "application/json" }.merge(headers), body.is_a?(String) ? body : JSON.generate(body)]
  end

  def problem(status, fields = {}, headers = {})
    [status, { "content-type" => "application/problem+json" }.merge(headers), JSON.generate({ "status" => status, **fields })]
  end

  def teardown
    @clients&.each(&:close)
    @servers&.each(&:close)
    super
  end
end
