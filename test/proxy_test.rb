# frozen_string_literal: true

require_relative "test_helper"

class ProxyTest < SynthientTest
  PROXY_VARIABLES = %w[http_proxy HTTP_PROXY https_proxy HTTPS_PROXY no_proxy NO_PROXY].freeze
  # The .invalid TLD never resolves, so a request that skipped the proxy fails.
  API_URL = "https://api.synthient.invalid/api/v4"

  # Routes Net::HTTP through +proxy+ with http_proxy, which it also uses for
  # HTTPS, and restores every proxy variable afterwards.
  def with_proxy(proxy)
    saved = PROXY_VARIABLES.to_h { |name| [name, ENV.fetch(name, nil)] }
    begin
      PROXY_VARIABLES.each { |name| ENV.delete(name) }
      ENV["http_proxy"] = "http://127.0.0.1:#{proxy.port}"
      yield
    ensure
      saved.each { |name, value| ENV[name] = value }
    end
  end

  def test_refused_connect_raises_connection_error
    { 407 => Net::HTTPClientException, 502 => Net::HTTPFatalError }.each do |status, cause|
      proxy = serve { [status, {}, ""] }
      with_proxy(proxy) do
        client = new_client(proxy, base_url: API_URL)

        error = assert_raises(Synthient::ConnectionError, "CONNECT #{status}") { client.account }
        assert_kind_of cause, error.cause
        assert_equal 3, proxy.requests.size, "account retries a refused CONNECT"

        error = assert_raises(Synthient::ConnectionError, "CONNECT #{status}") { client.lookup_ip("8.8.8.8") }
        assert_kind_of cause, error.cause
        assert_equal 4, proxy.requests.size, "a lookup does not retry a refused CONNECT"

        assert_raises(Synthient::ConnectionError, "CONNECT #{status}") { client.proxies.stream { flunk "unexpected event" } }
        assert_equal 7, proxy.requests.size, "a stream retries a refused CONNECT"
      end
      assert(proxy.requests.all? { |request| request.verb == "CONNECT" && request.path == "api.synthient.invalid:443" })
    end
  end
end
