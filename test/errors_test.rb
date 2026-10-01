# frozen_string_literal: true

require_relative "test_helper"

class ErrorsTest < SynthientTest
  def api_error(response, max_retries: 0)
    server = serve { response }
    assert_raises(Synthient::APIError) { new_client(server, max_retries:).account }
  end

  def test_problem_details
    error = api_error(problem(403, { "type" => "about:blank", "title" => "Forbidden", "detail" => "missing scope",
                                     "instance" => "inst-1" }, "x-request-id" => "req-1"))

    assert_equal 403, error.status
    assert_equal "about:blank", error.type
    assert_equal "Forbidden", error.title
    assert_equal "missing scope", error.detail
    assert_equal "req-1", error.request_id
    assert_empty error.errors
    assert_nil error.retry_after
  end

  def test_request_id_falls_back_to_instance
    assert_equal "inst-1", api_error(problem(404, { "instance" => "inst-1" })).request_id
  end

  def test_validation_errors
    error = api_error(problem(422, { "title" => "Unprocessable", "errors" => { "ips" => ["must not be empty"] } }))

    assert_equal({ "ips" => ["must not be empty"] }, error.errors)
    assert_nil error.detail
  end

  def test_malformed_fields_are_dropped
    error = api_error(problem(422, { "title" => 7, "detail" => "kept", "errors" => %w[not a map] }))

    assert_nil error.title
    assert_equal "kept", error.detail
    assert_empty error.errors
    assert_empty api_error(problem(422, { "errors" => { "ips" => "nope" } })).errors
  end

  def test_text_plain_body_becomes_detail
    error = api_error([401, { "content-type" => "text/plain; charset=utf-8" }, "401 invalid api key\n"])

    assert_equal 401, error.status
    assert_equal "401 invalid api key", error.detail
  end

  def test_empty_rate_limit_response
    error = api_error([429, { "retry-after" => "7" }, ""])

    assert_equal 429, error.status
    assert_equal 7, error.retry_after
    assert_nil error.detail
  end

  def test_large_html_body
    error = api_error([502, { "content-type" => "text/html" }, "<html>#{"x" * (128 << 10)}</html>"])

    assert_equal 502, error.status
    assert_nil error.detail
    assert_nil error.title
  end

  def test_body_read_failure_keeps_status
    server = serve do |_, socket|
      socket.write("HTTP/1.1 503 Unavailable\r\nx-request-id: req-9\r\ncontent-length: 100\r\n\r\n{\"title\":")
      :close
    end
    error = assert_raises(Synthient::APIError) { new_client(server, max_retries: 0).account }

    assert_equal 503, error.status
    assert_equal "req-9", error.request_id
    assert_kind_of Synthient::ConnectionError, error.cause
  end

  def test_messages
    assert_equal "429 Too Many Requests", Synthient::APIError.new(status: 429).message
    assert_equal "422 Unprocessable Entity", Synthient::APIError.new(status: 422).message
    assert_equal "418", Synthient::APIError.new(status: 418).message
  end

  def test_messages_contain_no_secrets
    server = serve do
      problem(403, { "detail" => "key test-key cannot read secret.example.com" }, "x-request-id" => "r")
    end
    error = assert_raises(Synthient::APIError) { new_client(server).lookup_domain("secret.example.com") }

    ["test-key", "secret.example.com", "127.0.0.1", "/api/v4"].each do |secret|
      refute_includes error.message, secret
      refute_includes error.detailed_message, secret
      refute_includes error.inspect, secret
    end
  end

  def test_invalid_success_bodies
    {
      "not json" => "{",
      "trailing data" => "{} x",
      "not an object" => "[1]",
      "nested too deep" => "#{"[" * 200}#{"]" * 200}"
    }.each do |name, body|
      server = serve { json(200, body) }

      assert_raises(Synthient::DecodeError, name) { new_client(server).account }
    end
  end

  def test_oversized_success_body
    server = serve { json(200, %({"email":"#{"x" * (16 << 20)}"})) }
    error = assert_raises(Synthient::DecodeError) { new_client(server).account }

    assert_equal "response body exceeds #{16 << 20} bytes", error.message
  end

  def test_gzip_bodies
    gzipped = Zlib.gzip(JSON.generate(ACCOUNT))
    server = serve { [200, { "content-type" => "application/json", "content-encoding" => "gzip" }, gzipped] }

    assert_equal "dev@example.com", new_client(server).account.email
    assert_includes server.requests.first.headers["accept-encoding"], "gzip"

    broken = serve { [200, { "content-type" => "application/json", "content-encoding" => "gzip" }, "not gzip at all"] }

    assert_raises(Synthient::DecodeError) { new_client(broken).account }
  end
end
