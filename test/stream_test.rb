# frozen_string_literal: true

require_relative "test_helper"

class StreamTest < SynthientTest
  META = { "proxy_ip" => "203.0.113.10", "server" => "hp-eu-1", "pool_id" => "prod", "provider" => "luminati" }.freeze

  EVENTS = {
    proxies: {
      "ip" => "198.51.100.4", "provider" => "BRIGHTDATA", "type" => "RESIDENTIAL_PROXY", "country_code" => "US",
      "asn" => 4_294_967_295, "timestamp" => 1_778_187_600
    },
    anonymizers: {
      "range_start" => "198.51.100.0", "range_end" => "198.51.100.255", "provider" => "NORDVPN",
      "type" => "COMMERCIAL_VPN", "country_code" => "NL", "asn" => 9009, "timestamp" => 1_778_200_137_487
    },
    torrents: {
      "info_hash" => "c9e15763f722f23e98a29decdfae341b98d53056", "name" => "ubuntu.iso", "magnet_uri" => "magnet:?xt=1",
      "total_size" => 5_000_000_000, "piece_length" => 262_144, "file_count" => 1,
      "files" => [{ "path" => "ubuntu.iso", "length" => 5_000_000_000 }],
      "peers" => [{ "ip" => "192.0.2.8", "port" => 6881, "source" => "DHT", "encrypted" => true }],
      "timestamp" => 1_778_187_600
    },
    ja4t: {
      "ip" => "192.0.2.9", "ja4t" => "64240_2-4-8-1-3_1460_8", "provider" => "AWS", "type" => "DATACENTER_PROXY",
      "country_code" => "US", "asn" => 16_509, "timestamp" => 1_778_187_600
    },
    helios_http: {
      "timestamp" => 1_778_200_137_487, "tunnel_id" => 1_942_782, "domain" => "example.com", "port" => 80,
      "protocol" => "http", "meta" => META,
      "details" => { "method" => "GET", "uri" => "/", "version" => "HTTP/1.1", "headers" => { "Host" => "example.com" } },
      "raw" => ["GET / HTTP/1.1\r\n"].pack("m0")
    },
    helios_https: {
      "timestamp" => 1_778_200_137_487, "tunnel_id" => 17_257_744_507_466_107_949, "domain" => "example.com",
      "port" => 443, "protocol" => "https", "meta" => META,
      "details" => {
        "handshake_version" => "TLS 1.2", "sni" => "example.com",
        "cipher_suites" => [{ "code" => 4865, "name" => "TLS_AES_128_GCM_SHA256" }],
        "extensions" => [{ "code" => 0, "name" => "server_name", "length" => 16 }],
        "alpn" => ["h2", "http/1.1"], "has_grease" => true, "future_field" => 1
      },
      "raw" => nil
    },
    helios_dns: {
      "timestamp" => 1_778_200_137_487, "tunnel_id" => 7, "domain" => "203.0.113.50", "port" => 53,
      "protocol" => "dns", "meta" => META
    },
    helios_adb: {
      "session" => "0123456789abcdef0123456789abcdef", "sequential_id" => 3, "command" => "uname -a",
      "hash" => "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
  }.freeze

  def chunked(socket, *chunks, finish: true)
    socket.write("HTTP/1.1 200 OK\r\ncontent-type: application/x-ndjson\r\ntransfer-encoding: chunked\r\n\r\n")
    chunks.each { |chunk| socket.write("#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n") unless chunk.empty? }
    socket.write("0\r\n\r\n") if finish
    :close
  end

  def ndjson(*events)
    events.map { |event| "#{JSON.generate(event)}\n" }.join
  end

  def test_every_feed
    EVENTS.each do |feed, event|
      server = serve { |_, socket| chunked(socket, ndjson(event)) }
      events = []
      new_client(server).public_send(feed).stream { |e| events << e }

      assert_equal 1, events.size, feed.to_s
      assert_match(%r{/stream\z}, server.paths.first)
      assert_equal "application/x-ndjson", server.requests.first.headers["accept"]
    end
  end

  def test_event_fields
    events = EVENTS.to_h do |feed, event|
      server = serve { |_, socket| chunked(socket, ndjson(event)) }
      [feed, new_client(server).public_send(feed).stream.first]
    end

    assert_equal ["/api/v4/feeds/helio/adb/stream"], @servers.last.paths
    assert_equal 4_294_967_295, events[:proxies].asn
    assert_equal Time.at(1_778_187_600, in: "UTC"), events[:proxies].timestamp
    assert_equal Time.at(1_778_200_137, 487, :millisecond, in: "UTC"), events[:anonymizers].timestamp
    assert events[:torrents].peers.first.encrypted
    assert_equal "GET", events[:helios_http].details.http_method
    assert_equal({ "Host" => "example.com" }, events[:helios_http].details.headers)
    assert_equal "GET / HTTP/1.1\r\n".b, events[:helios_http].raw
    assert_equal 17_257_744_507_466_107_949, events[:helios_https].tunnel_id
    assert_equal ["h2", "http/1.1"], events[:helios_https].details.alpn
    assert_nil events[:helios_https].raw
    assert_equal "203.0.113.50", events[:helios_dns].domain
    assert_equal "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", events[:helios_adb].payload_hash
  end

  def test_https_details_may_be_null
    server = serve { |_, socket| chunked(socket, ndjson(EVENTS[:helios_https].merge("details" => nil))) }

    assert_nil new_client(server).helios_https.stream.first.details
  end

  def test_split_at_every_byte_offset
    payload = "#{JSON.generate(EVENTS[:proxies].merge("provider" => "Ünïcödé"))}\r\n\n   \n" \
              "#{JSON.generate(EVENTS[:proxies])}\n\n#{JSON.generate(EVENTS[:proxies])}\n"
    offset = 0
    server = serve { |_, socket| chunked(socket, payload.byteslice(0, offset), payload.byteslice(offset..)) }
    client = new_client(server)
    (1...payload.bytesize).each do |split|
      offset = split
      events = []
      client.proxies.stream { |event| events << event }

      assert_equal %w[Ünïcödé BRIGHTDATA BRIGHTDATA], events.map(&:provider), "split at #{split}"
    end
  end

  def test_final_line_without_newline
    server = serve { |_, socket| chunked(socket, "#{ndjson(EVENTS[:proxies])}#{JSON.generate(EVENTS[:proxies])}") }

    assert_equal 2, new_client(server).proxies.stream.to_a.size
  end

  def test_invalid_final_line_raises_after_earlier_events
    server = serve { |_, socket| chunked(socket, "#{ndjson(EVENTS[:proxies])}{\"ip\":") }
    events = []
    assert_raises(Synthient::DecodeError) { new_client(server).proxies.stream { |event| events << event } }

    assert_equal 1, events.size
  end

  def test_invalid_events
    ["not json\n", "[1]\n", "#{JSON.generate(EVENTS[:helios_dns].except("tunnel_id"))}\n"].each do |line|
      server = serve { |_, socket| chunked(socket, line) }

      assert_raises(Synthient::DecodeError, line) { new_client(server).helios_dns.stream.to_a }
    end
  end

  def test_event_size_limit
    limit = 16 << 20
    [["x" * (limit + 1), ""], ["#{"x" * (limit + 1)}\n", ""]].each do |chunks|
      server = serve { |_, socket| chunked(socket, *chunks) }
      error = assert_raises(Synthient::DecodeError) { new_client(server).proxies.stream.to_a }

      assert_equal "stream event exceeds #{limit} bytes", error.message
    end
  end

  def test_rejected_streams_are_not_retried
    [problem(403, { "title" => "Forbidden" }), problem(429, { "title" => "Too many streams" })].each do |response|
      server = serve { response }
      error = assert_raises(Synthient::APIError) { new_client(server).proxies.stream.to_a }

      assert_equal response[0], error.status
      assert_equal 1, server.requests.size
    end
  end

  def test_connect_is_retried
    count = 0
    server = serve do |_, socket|
      count += 1
      count == 1 ? json(503, {}) : chunked(socket, ndjson(EVENTS[:proxies]))
    end

    assert_equal 1, new_client(server).proxies.stream.to_a.size
    assert_equal 2, server.requests.size
  end

  def test_requires_exactly_ok
    server = serve { json(201, {}) }
    error = assert_raises(Synthient::APIError) { new_client(server).proxies.stream.to_a }

    assert_equal 201, error.status
  end

  def test_connection_drop_mid_stream
    server = serve { |_, socket| chunked(socket, ndjson(EVENTS[:proxies]), "{\"ip\":", finish: false) }
    events = []
    assert_raises(Synthient::ConnectionError) { new_client(server).proxies.stream { |event| events << event } }

    assert_equal 1, events.size
  end

  def test_break_closes_the_connection
    disconnected = Queue.new
    server = serve do |_, socket|
      chunked(socket, ndjson(EVENTS[:proxies]), finish: false)
      disconnected << socket.read
      :close
    end
    client = new_client(server)
    client.proxies.stream { break }

    assert_equal "", Timeout.timeout(5) { disconnected.pop }
  end

  def test_enumerator_opens_the_connection_lazily
    server = serve { |_, socket| chunked(socket, ndjson(EVENTS[:proxies], EVENTS[:proxies], EVENTS[:proxies])) }
    events = new_client(server).proxies.stream

    assert_kind_of Enumerator, events
    assert_empty server.requests
    assert_equal 2, events.first(2).size
    assert_equal 1, server.requests.size
  end

  def test_block_exceptions_pass_through
    server = serve { |_, socket| chunked(socket, ndjson(EVENTS[:proxies])) }

    assert_raises(IOError) { new_client(server).proxies.stream { raise IOError, "caller failure" } }
    assert_raises(StopIteration) { new_client(server).proxies.stream { raise StopIteration } }
    assert_equal 2, server.requests.size
  end
end
