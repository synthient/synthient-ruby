# frozen_string_literal: true

require_relative "test_helper"

class DownloadTest < SynthientTest
  PARQUET = "PAR1#{"\x00\xFF".b * 1000}PAR1".b.freeze
  SIGNED_PATH = "/proxies/2026-05-07.parquet?X-Amz-Signature=secret-signature"

  def storage(&)
    server = serve(&)
    # Storage is reached as localhost so it is a different origin from the API at 127.0.0.1.
    [server, "http://localhost:#{server.port}"]
  end

  def api(location, status: 307)
    serve { [status, { "location" => location }, ""] }
  end

  def download(client, export = "2026-05-07")
    data = "".b
    client.proxies.download(export) { |chunk| data << chunk }
    data
  end

  def test_download
    store, origin = storage { [200, { "content-type" => "application/octet-stream" }, PARQUET] }
    server = api("#{origin}#{SIGNED_PATH}")

    assert_equal PARQUET, download(new_client(server, user_agent: "app/1"))
    assert_equal ["/api/v4/feeds/proxies/export/2026-05-07"], server.paths
    request = store.requests.first

    assert_equal SIGNED_PATH, request.path
    assert_nil request.headers["x-api-key"]
    assert_equal "synthient-ruby/#{Synthient::VERSION} app/1", request.headers["user-agent"]
    assert_equal "identity", request.headers["accept-encoding"]
  end

  def test_download_url
    _, origin = storage { [200, {}, ""] }
    server = api("#{origin}#{SIGNED_PATH}")
    url = new_client(server).proxies.download_url("2026-05-07/7")

    assert_equal URI("#{origin}#{SIGNED_PATH}"), url
    assert_equal ["/api/v4/feeds/proxies/export/2026-05-07/7"], server.paths
  end

  def test_relative_location
    server = api("/storage/file.parquet?sig=1")

    assert_equal URI(server.url("/storage/file.parquet?sig=1")), new_client(server).proxies.download_url("latest")
  end

  def test_https_api_rejects_http_redirect
    client = new_client(api("http://storage.test/file"))
    client.instance_variable_get(:@transport).instance_variable_set(:@base_scheme, "https")
    error = assert_raises(Synthient::DecodeError) { client.proxies.download_url("latest") }

    assert_equal "export redirect does not use https", error.message
  end

  def test_invalid_locations
    ["", "ftp://storage.test/file", "http://user:pass@storage.test/file", "http://", "http://[bad"].each do |location|
      server = api(location)
      error = assert_raises(Synthient::DecodeError, location) { new_client(server).proxies.download_url("latest") }

      assert_equal "export redirect has no valid location", error.message
    end
  end

  def test_not_a_redirect
    server = serve { json(200, {}) }
    error = assert_raises(Synthient::DecodeError) { new_client(server).proxies.download_url("latest") }

    assert_equal "expected a redirect to the export, got status 200", error.message
  end

  def test_daily_export_in_progress
    server = serve { problem(404, { "title" => "Export not ready" }, "retry-after" => "120") }
    error = assert_raises(Synthient::APIError) { new_client(server).proxies.download("2026-05-07") { nil } }

    assert_equal 404, error.status
    assert_equal 120, error.retry_after
  end

  def test_storage_redirects
    store, origin = storage do |request|
      case request.path
      when "/a" then [302, { "location" => "/b" }, ""]
      when "/b" then [307, { "location" => "#{origin}/c" }, ""]
      else [200, {}, PARQUET]
      end
    end

    assert_equal PARQUET, download(new_client(api("#{origin}/a")))
    assert_equal %w[/a /b /c], store.paths
  end

  def test_storage_downgrade_is_blocked
    insecure = serve { [200, {}, PARQUET] }
    client = new_client(api("https://localhost:1/file"))
    transport = client.instance_variable_get(:@transport)
    redirect = Net::HTTPFound.new("1.1", "302", "Found")
    redirect["location"] = insecure.url("/file")
    real_start_session = transport.method(:start_session)
    transport.define_singleton_method(:start_session) do |uri|
      next real_start_session.call(uri) unless uri.host == "localhost"
      raise "unexpected request to #{uri}" unless uri.scheme == "https"

      session = Object.new
      session.define_singleton_method(:request) do |_, &block|
        redirect.uri = uri
        block.call(redirect)
      end
      session.define_singleton_method(:started?) { false }
      session
    end
    error = assert_raises(Synthient::Error) { download(client) }

    assert_equal "export redirect downgrades to http", error.message
    assert_empty insecure.requests
  end

  def test_too_many_storage_redirects
    store, origin = storage { |request| [302, { "location" => "#{request.path}x" }, ""] }
    error = assert_raises(Synthient::Error) { download(new_client(api("#{origin}/r"))) }

    assert_equal "too many export redirects", error.message
    assert_equal 11, store.requests.size
  end

  def test_storage_errors
    _, origin = storage { [403, { "content-type" => "application/xml" }, "<Error>AccessDenied</Error>"] }
    error = assert_raises(Synthient::APIError) { download(new_client(api("#{origin}#{SIGNED_PATH}"))) }

    assert_equal 403, error.status
    refute_includes error.message, "secret-signature"
  end

  def test_storage_unreachable
    port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
    error = assert_raises(Synthient::ConnectionError) do
      download(new_client(api("http://localhost:#{port}#{SIGNED_PATH}")))
    end

    refute_includes error.message, "secret-signature"
  end

  def test_truncated_download_raises
    _, origin = storage do |_, socket|
      socket.write("HTTP/1.1 200 OK\r\ncontent-length: #{PARQUET.bytesize}\r\n\r\n#{PARQUET.byteslice(0, 100)}")
      :close
    end
    received = "".b
    assert_raises(Synthient::ConnectionError) do
      new_client(api("#{origin}/file")).proxies.download("latest") { |chunk| received << chunk }
    end

    assert_equal PARQUET.byteslice(0, 100), received
  end

  def test_break_closes_the_connection
    disconnected = Queue.new
    _, origin = storage do |_, socket|
      socket.write("HTTP/1.1 200 OK\r\ncontent-length: #{PARQUET.bytesize * 2}\r\n\r\n#{PARQUET}")
      disconnected << socket.read
      :close
    end
    new_client(api("#{origin}/file")).proxies.download("latest") { break }

    assert_equal "", Timeout.timeout(5) { disconnected.pop }
  end

  def test_enumerator_form
    _, origin = storage { [200, {}, PARQUET] }
    chunks = new_client(api("#{origin}/file")).proxies.download("latest")

    assert_kind_of Enumerator, chunks
    assert_equal PARQUET, chunks.to_a.join
  end
end
