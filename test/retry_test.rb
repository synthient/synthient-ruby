# frozen_string_literal: true

require_relative "test_helper"

class RetryTest < SynthientTest
  def respond_then_succeed(first, success: json(200, ACCOUNT))
    count = 0
    serve do
      count += 1
      count == 1 ? first : success
    end
  end

  def test_retry_policy
    rate_limited = json(429, {}, "retry-after" => "0")
    cases = [
      ["account", ->(c) { c.account }, rate_limited, true],
      ["account", ->(c) { c.account }, json(429, {}), false],
      ["account", ->(c) { c.account }, json(500, {}), true],
      ["account", ->(c) { c.account }, json(503, {}), true],
      ["account", ->(c) { c.account }, json(501, {}), false],
      ["account", ->(c) { c.account }, json(400, {}), false],
      ["lookup", ->(c) { c.lookup_ip("8.8.8.8") }, rate_limited, true],
      ["lookup", ->(c) { c.lookup_ip("8.8.8.8") }, json(429, {}), false],
      ["lookup", ->(c) { c.lookup_ip("8.8.8.8") }, json(503, {}), false],
      ["batch", ->(c) { c.lookup_ips(["8.8.8.8"]) }, json(502, {}), false],
      ["domain", ->(c) { c.lookup_domain("example.com") }, json(500, {}), false],
      ["health", ->(c) { c.health }, json(503, {}), false],
      ["exports", ->(c) { c.proxies.list_exports }, json(504, {}), true]
    ]
    cases.each do |name, call, first, retried|
      server = respond_then_succeed(first)
      begin
        call.call(new_client(server))
      rescue Synthient::Error
        nil
      end

      assert_equal retried ? 2 : 1, server.requests.size, "#{name} #{first[0]} #{first[1]}"
    end
  end

  def test_honors_retry_after
    server = respond_then_succeed(json(429, {}, "retry-after" => "3"))
    new_client(server).account

    assert_equal [3], sleeps
  end

  def test_backoff_when_retry_after_is_shorter
    server = respond_then_succeed(json(429, {}, "retry-after" => "0"))
    new_client(server).account

    assert_equal [1.0], sleeps
  end

  def test_unparsable_retry_after_retries_with_backoff
    server = respond_then_succeed(json(429, {}, "retry-after" => "soon"))
    new_client(server).account

    assert_equal 2, server.requests.size
    assert_equal [1.0], sleeps
  end

  def test_stops_when_retry_after_is_too_long
    server = respond_then_succeed(json(429, {}, "retry-after" => "120"))
    error = assert_raises(Synthient::APIError) { new_client(server).account }

    assert_equal 429, error.status
    assert_equal 120, error.retry_after
    assert_equal 1, server.requests.size
    assert_empty sleeps
  end

  def test_gives_up_after_max_retries
    server = serve { json(503, {}) }
    error = assert_raises(Synthient::APIError) { new_client(server, max_retries: 3).account }

    assert_equal 503, error.status
    assert_equal 4, server.requests.size
    assert_equal [1.0, 2.0, 4.0], sleeps
  end

  def test_zero_retries
    server = serve { json(429, {}, "retry-after" => "0") }
    assert_raises(Synthient::APIError) { new_client(server, max_retries: 0).account }

    assert_equal 1, server.requests.size
  end

  def test_backoff_bounds
    transport = Synthient::Client.new(api_key: API_KEY).instance_variable_get(:@transport)
    jitter = 0.0
    transport.define_singleton_method(:rand) { jitter }
    [[0, 1], [1, 2], [2, 4], [4, 16], [5, 30], [9, 30]].each do |attempt, base|
      jitter = 0.0

      assert_in_delta base * 0.75, transport.send(:backoff, attempt)
      jitter = 0.999999

      assert_in_delta base * 1.25, transport.send(:backoff, attempt), 0.001
    end
  end

  def test_parse_retry_after
    now = Time.now
    cases = {
      nil => nil, "" => nil, "  " => nil, "soon" => nil, "1.5" => nil,
      "0" => 0, "7" => 7, " 7 " => 7, "007" => 7, "-3" => 0, "99999999999" => 2**31,
      (now - 60).httpdate => 0
    }
    cases.each do |value, expected|
      actual = Synthient::Transport.parse_retry_after(value)

      expected.nil? ? assert_nil(actual, value.inspect) : assert_equal(expected, actual, value.inspect)
    end
    future = Synthient::Transport.parse_retry_after((now + 30).httpdate)

    assert_in_delta 30, future, 2
    rfc850 = Synthient::Transport.parse_retry_after((now + 30).utc.strftime("%A, %d-%b-%y %H:%M:%S GMT"))

    assert_in_delta 30, rfc850, 2
  end

  def test_transport_errors_are_retried_only_for_free_requests
    count = 0
    server = serve do
      count += 1
      count == 1 ? :close : json(200, ACCOUNT)
    end
    new_client(server).account

    assert_equal 2, server.requests.size

    count = 0
    lookups = serve do
      count += 1
      count == 1 ? :close : json(200, IP_INFO)
    end
    assert_raises(Synthient::ConnectionError) { new_client(lookups).lookup_ip("8.8.8.8") }
    assert_equal 1, lookups.requests.size
  end

  def test_billed_requests_are_not_replayed_on_a_reused_connection
    {
      "/api/v4/lookup/ip/8.8.8.8" => ->(c) { c.lookup_ip("8.8.8.8") },
      "/api/v4/lookup/domain/example.com" => ->(c) { c.lookup_domain("example.com") },
      "/api/v4/lookup/ips" => ->(c) { c.lookup_ips(["8.8.8.8"]) }
    }.each do |path, call|
      server = serve { |request| request.path.end_with?("/health") ? json(200, {}) : :close }
      client = new_client(server)
      client.health

      assert_raises(Synthient::ConnectionError, path) { call.call(client) }
      requests = server.requests

      assert_equal 1, requests.count { |request| request.path == path }, path
      assert_equal requests.first.connection, requests.last.connection, "the lookup should reuse the warm connection"
    end
  end

  def test_errors_while_reading_the_body_are_not_retried
    server = serve do |_, socket|
      socket.write("HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: 100\r\n\r\n{\"email\":")
      :close
    end
    error = assert_raises(Synthient::ConnectionError) { new_client(server).account }

    assert_kind_of EOFError, error.cause
    assert_equal 1, server.requests.size
  end

  def test_read_timeout
    server = serve do |_, socket|
      sleep 1
      socket.write("HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\n{}")
      :close
    end

    assert_raises(Synthient::TimeoutError) { new_client(server, timeout: 0.1, max_retries: 0).account }
  end

  def test_connection_refused
    port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
    client = Synthient::Client.new(api_key: API_KEY, base_url: "http://127.0.0.1:#{port}/api/v4", max_retries: 0)
    error = assert_raises(Synthient::ConnectionError) { client.account }

    assert_kind_of SystemCallError, error.cause
  end
end
