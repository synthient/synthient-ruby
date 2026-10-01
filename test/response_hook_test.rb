# frozen_string_literal: true

require_relative "test_helper"

class ResponseHookTest < SynthientTest
  def recorder
    seen = []
    [seen, ->(metadata) { seen << metadata }]
  end

  def test_sees_retries_and_rate_limits
    seen, hook = recorder
    count = 0
    server = serve do
      count += 1
      next json(429, {}, "retry-after" => "0", "x-request-id" => "r1") if count == 1

      json(200, ACCOUNT, "x-request-id" => "r2", "ratelimit-limit" => "10", "ratelimit-remaining" => "9",
                         "ratelimit-reset" => "1")
    end
    new_client(server, response_hook: hook).account

    assert_equal [429, 200], seen.map(&:status)
    assert_equal %w[r1 r2], seen.map(&:request_id)
    assert_nil seen[0].rate_limit
    assert_equal Synthient::RateLimit.new(limit: 10, remaining: 9, reset: 1), seen[1].rate_limit
    assert_predicate seen[1].headers, :frozen?
    assert_equal "r2", seen[1].headers["x-request-id"]
  end

  def test_rate_limit_parsing
    {
      { "ratelimit-limit" => "200", "ratelimit-remaining" => "0", "ratelimit-reset" => "99999999999" } =>
        Synthient::RateLimit.new(limit: 200, remaining: 0, reset: 2**31),
      { "ratelimit-limit" => "200", "ratelimit-remaining" => "5" } => nil,
      { "ratelimit-limit" => "x", "ratelimit-remaining" => "5", "ratelimit-reset" => "1" } => nil,
      { "ratelimit-limit" => "200", "ratelimit-remaining" => "-1", "ratelimit-reset" => "1" } => nil
    }.each do |headers, expected|
      seen, hook = recorder
      new_client(serve { json(200, {}, headers) }, response_hook: hook).health

      expected.nil? ? assert_nil(seen.first.rate_limit) : assert_equal(expected, seen.first.rate_limit)
    end
  end

  def test_sees_pages_stream_handshakes_and_decode_failures
    seen, hook = recorder
    server = serve do |request, socket|
      case request.path
      when /stream/
        socket.write("HTTP/1.1 200 OK\r\ncontent-length: 0\r\n\r\n")
        :close
      when /cursor/ then json(200, { "stream" => "proxies", "feeds" => [] })
      when /export/ then json(200, { "stream" => "proxies", "feeds" => [], "next_cursor" => "c1" })
      else json(200, { "email" => 1 })
      end
    end
    client = new_client(server, response_hook: hook)
    client.proxies.each_export.to_a
    client.proxies.stream.to_a
    assert_raises(Synthient::DecodeError) { client.account }

    assert_equal 4, seen.size
  end

  def test_not_called_for_storage
    seen, hook = recorder
    store = serve { [200, {}, "PAR1"] }
    server = serve { [307, { "location" => "http://localhost:#{store.port}/file" }, ""] }
    new_client(server, response_hook: hook).proxies.download("latest") { nil }

    assert_equal [307], seen.map(&:status)
  end

  def test_exceptions_propagate
    server = serve { json(200, {}) }
    hook = ->(_) { raise IOError, "hook failed" }

    assert_raises(IOError) { new_client(server, response_hook: hook).health }
    assert_equal 1, server.requests.size
  end

  def test_concurrent_requests_report_their_own_metadata
    seen = Queue.new
    server = serve { |request| json(200, IP_INFO, "x-request-id" => request.path.split("/").last) }
    client = new_client(server, response_hook: ->(metadata) { seen << metadata.request_id })
    ips = (1..20).map { |n| "10.0.1.#{n}" }
    ips.map { |ip| Thread.new { client.lookup_ip(ip) } }.each(&:join)

    assert_equal ips.sort, Array.new(seen.size) { seen.pop }.sort
  end
end
