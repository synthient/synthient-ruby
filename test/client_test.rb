# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < SynthientTest
  def with_env(name, value)
    previous = ENV.fetch(name, nil)
    ENV[name] = value
    yield
  ensure
    ENV[name] = previous
  end

  def test_reads_api_key_from_environment
    server = serve { json(200, {}) }
    with_env("SYNTHIENT_API_KEY", " env-key\n") do
      client = Synthient::Client.new(base_url: server.url)
      client.health
      client.close
    end

    assert_equal "env-key", server.requests.first.headers["x-api-key"]
  end

  def test_missing_api_key
    with_env("SYNTHIENT_API_KEY", nil) do
      assert_raises(ArgumentError) { Synthient::Client.new }
    end
    assert_raises(ArgumentError) { Synthient::Client.new(api_key: "  ") }
    assert_raises(ArgumentError) { Synthient::Client.new(api_key: "a\nb") }
    assert_raises(TypeError) { Synthient::Client.new(api_key: 123) }
  end

  def test_invalid_base_urls
    [
      "ftp://api.test/api/v4", "https://", "https://api.test/api/v4?x=1", "https://api.test/api/v4#frag",
      "https://user:pass@api.test/api/v4", "https://api.test/%zz", "not a url"
    ].each do |url|
      assert_raises(ArgumentError, url) { Synthient::Client.new(api_key: API_KEY, base_url: url) }
    end
  end

  def test_base_url_trailing_slash_is_trimmed
    server = serve { json(200, {}) }
    new_client(server, base_url: "#{server.url}/").health

    assert_equal ["/api/v4/health"], server.paths
  end

  def test_invalid_options
    assert_raises(ArgumentError) { Synthient::Client.new(api_key: API_KEY, max_retries: -1) }
    assert_raises(ArgumentError) { Synthient::Client.new(api_key: API_KEY, max_retries: 1.5) }
    assert_raises(ArgumentError) { Synthient::Client.new(api_key: API_KEY, max_retries: "2") }
    [0, -1, Float::INFINITY, Float::NAN, "5", nil, Complex(1, 1)].each do |value|
      assert_raises(ArgumentError, value.inspect) { Synthient::Client.new(api_key: API_KEY, timeout: value) }
      assert_raises(ArgumentError, value.inspect) { Synthient::Client.new(api_key: API_KEY, open_timeout: value) }
    end
    assert_raises(TypeError) { Synthient::Client.new(api_key: API_KEY, response_hook: "hook") }
    assert_raises(ArgumentError) { Synthient::Client.new(api_key: API_KEY, user_agent: "a\r\nX-Evil: 1") }
  end

  def test_fractional_timeouts_are_kept
    server = serve { json(200, {}) }
    client = new_client(server, timeout: 1.5, open_timeout: Rational(1, 4))
    session = client.instance_variable_get(:@transport).send(:start_session, URI(server.url))

    assert_in_delta 1.5, session.read_timeout
    assert_in_delta 1.5, session.write_timeout
    assert_equal Rational(1, 4), session.open_timeout
    assert_equal 0, session.max_retries
    refute session.ignore_eof
  ensure
    session&.finish
  end

  def test_request_headers
    server = serve { json(200, IP_INFO) }
    new_client(server).lookup_ip("8.8.8.8")
    request = server.requests.first

    assert_equal "GET", request.verb
    assert_equal "/api/v4/lookup/ip/8.8.8.8", request.path
    assert_equal API_KEY, request.headers["x-api-key"]
    assert_equal "synthient-ruby/#{Synthient::VERSION}", request.headers["user-agent"]
    assert_equal "application/json", request.headers["accept"]
    refute request.headers.key?("content-type")
  end

  def test_user_agent_suffix
    server = serve { json(200, {}) }
    new_client(server, user_agent: "my-app/2.0").health

    assert_equal "synthient-ruby/#{Synthient::VERSION} my-app/2.0", server.requests.first.headers["user-agent"]
  end

  def test_inspect_hides_api_key
    client = Synthient::Client.new(api_key: "secret-key-value")

    refute_includes client.inspect, "secret-key-value"
    refute_includes client.instance_variable_get(:@transport).inspect, "secret-key-value"
  end

  def test_connections_are_reused
    server = serve { json(200, {}) }
    client = new_client(server)
    3.times { client.health }

    assert_equal [1, 1, 1], server.requests.map(&:connection)
  end

  def test_close_is_idempotent_and_rejects_later_requests
    server = serve { json(200, {}) }
    client = new_client(server)
    client.health

    assert_nil client.close
    assert_nil client.close
    assert_raises(IOError) { client.health }
    assert_raises(IOError) { client.proxies.list_exports }
  end

  def test_fork_does_not_reuse_parent_connections
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    server = serve { json(200, {}) }
    client = new_client(server)
    client.health
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      client.health
      writer.write("ok")
      exit!(0)
    end
    writer.close
    Process.wait(pid)

    assert_equal "ok", reader.read
    client.health

    assert_equal 3, server.requests.size
    assert_equal server.requests[0].connection, server.requests[2].connection
    refute_equal server.requests[0].connection, server.requests[1].connection
  end

  def test_concurrent_requests
    server = serve { |request| json(200, IP_INFO.merge("ip" => request.path.split("/").last)) }
    client = new_client(server)
    ips = (1..20).map { |n| "10.0.0.#{n}" }
    results = ips.map { |ip| Thread.new { client.lookup_ip(ip).ip.to_s } }.map(&:value)

    assert_equal ips, results
    assert_operator server.requests.map(&:connection).uniq.size, :<=, 20
  end
end
