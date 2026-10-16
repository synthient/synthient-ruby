# frozen_string_literal: true

module Synthient
  # A client for the Synthient API.
  #
  # A client holds a pool of keep-alive connections and is safe to share
  # between threads, so create one and reuse it. Call #close on shutdown. In a
  # forking server, connections inherited from the parent are never reused.
  #
  # Lookups are billed and are never resent after a network failure, because
  # the API may already have done the work. They are retried only when the API
  # answers 429 with a Retry-After header, which it does before any work.
  # Account and feed requests are also retried on 500, 502, 503, and 504
  # responses and on network failures other than TLS errors before a response
  # arrives. Retries wait with jittered exponential backoff, or as long as
  # Retry-After asks, and stop when Retry-After exceeds 60 seconds.
  #
  # @example
  #   client = Synthient::Client.new # reads SYNTHIENT_API_KEY
  #   info = client.lookup_ip("8.8.8.8")
  #   puts info.intelligence&.risk_score
  class Client
    MAX_BATCH_SIZE = 1000

    # @return [Feed<ProxyEvent>] proxy sightings
    attr_reader :proxies
    # @return [Feed<AnonymizerEvent>] VPN and anonymizer address ranges
    attr_reader :anonymizers
    # @return [Feed<TorrentEvent>] torrents seen on the BitTorrent DHT and trackers
    attr_reader :torrents
    # @return [Feed<JA4TEvent>] JA4T TCP fingerprint sightings
    attr_reader :ja4t
    # @return [Feed<HeliosHTTPEvent>] HTTP requests captured by Helios honeypots
    attr_reader :helios_http
    # @return [Feed<HeliosHTTPSEvent>] TLS ClientHellos captured by Helios honeypots
    attr_reader :helios_https
    # @return [Feed<HeliosDNSEvent>] destinations Helios honeypot tunnels were asked to reach
    attr_reader :helios_dns
    # @return [Feed<HeliosADBEvent>] ADB shell commands captured by Helios honeypots
    attr_reader :helios_adb

    # Creates a client. It makes no network requests.
    #
    # @param api_key [String] the API key, by default from SYNTHIENT_API_KEY
    # @param base_url [String]
    # @param max_retries [Integer] retries after the first attempt; 0 disables them
    # @param timeout [Numeric] seconds to wait for each read or write
    # @param open_timeout [Numeric] seconds to wait for a connection
    # @param user_agent [String, nil] appended to the SDK's User-Agent
    # @param response_hook [#call, nil] called with a ResponseMetadata for every
    #   API response, before its body is read. Exceptions it raises propagate.
    # @raise [ArgumentError] if the API key is missing or an option is invalid
    def initialize(api_key: ENV.fetch("SYNTHIENT_API_KEY", nil), base_url: DEFAULT_BASE_URL, max_retries: 2,
                   timeout: 60, open_timeout: 10, user_agent: nil, response_hook: nil)
      raise TypeError, "api_key must be a String" unless api_key.nil? || api_key.is_a?(String)

      api_key = api_key.to_s.strip
      raise ArgumentError, "missing API key: pass api_key: or set SYNTHIENT_API_KEY" if api_key.empty?
      raise ArgumentError, "API key contains a line break" if api_key.match?(/[\r\n]/)

      base_url = base_url.to_s.delete_suffix("/")
      uri = begin
        URI.parse(base_url)
      rescue URI::InvalidURIError
        nil
      end
      unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty? && uri.query.nil? && uri.fragment.nil? && uri.userinfo.nil?
        raise ArgumentError, "invalid base URL #{base_url.inspect}"
      end
      raise ArgumentError, "max_retries must be a non-negative Integer" unless max_retries.is_a?(Integer) && max_retries >= 0

      { timeout:, open_timeout: }.each do |name, value|
        unless value.is_a?(Numeric) && value.positive? && value.finite?
          raise ArgumentError, "#{name} must be a positive finite number of seconds"
        end
      end
      raise TypeError, "response_hook must respond to call" unless response_hook.nil? || response_hook.respond_to?(:call)
      raise ArgumentError, "user_agent contains a line break" if user_agent.to_s.match?(/[\r\n]/)

      agent = ["synthient-ruby/#{VERSION}", user_agent.to_s.strip].reject(&:empty?).join(" ")
      @base_url = base_url
      @transport = Transport.new(base_url:, api_key:, user_agent: agent, max_retries:, timeout:, open_timeout:,
                                 response_hook:)
      @proxies = Feed.new(@transport, "/feeds/proxies", ProxyEvent)
      @anonymizers = Feed.new(@transport, "/feeds/anonymizers", AnonymizerEvent)
      @torrents = Feed.new(@transport, "/feeds/torrents", TorrentEvent)
      @ja4t = Feed.new(@transport, "/feeds/ja4t", JA4TEvent)
      @helios_http = Feed.new(@transport, "/feeds/helio/http", HeliosHTTPEvent)
      @helios_https = Feed.new(@transport, "/feeds/helio/https", HeliosHTTPSEvent)
      @helios_dns = Feed.new(@transport, "/feeds/helio/dns", HeliosDNSEvent)
      @helios_adb = Feed.new(@transport, "/feeds/helio/adb", HeliosADBEvent)
    end

    # Looks up an IP address. Costs one lookup credit; failed lookups are free.
    #
    # @param ip [String, IPAddr] an IPv4 or IPv6 address, without a prefix or zone
    # @return [IPInfo]
    # @raise [APIError] for example 402 when credits run out
    def lookup_ip(ip)
      json = @transport.json("GET", "/lookup/ip/#{escape_path(canonical_ip(ip))}", policy: :rate_limit)
      Model.decode(IPInfo, json)
    end

    # Looks up to 1000 addresses in one request. The API drops duplicate,
    # private, and reserved addresses, so match results by +ip+, not position.
    # An invalid address raises ArgumentError before the request. Costs
    # ceil(n * 0.9) credits for n distinct usable addresses, and nothing if the
    # request fails. An empty list returns [] without a request.
    #
    # @param ips [Enumerable<String, IPAddr>]
    # @return [Array<IPInfo>]
    def lookup_ips(ips)
      raise TypeError, "ips must be Enumerable" unless ips.is_a?(Enumerable)

      ips = ips.to_a
      raise ArgumentError, "#{ips.size} addresses exceed the batch limit of #{MAX_BATCH_SIZE}" if ips.size > MAX_BATCH_SIZE
      return [] if ips.empty?

      addresses = ips.each_with_index.map do |ip, index|
        canonical_ip(ip)
      rescue ArgumentError, TypeError => e
        raise e.class, "#{e.message} at index #{index}"
      end
      json = @transport.json("POST", "/lookup/ips", policy: :rate_limit, body: JSON.generate({ ips: addresses }))
      Model.decode_value([IPInfo], json["results"] || raise(DecodeError, "IPBatch.results is required"), "IPBatch.results")
    end

    # Looks up the honeypot traffic Synthient has observed for a domain. Costs
    # one lookup credit. A domain that was never observed is +inactive+.
    #
    # @param domain [String]
    # @param limit [Integer, nil] how many recent events to return, 1 to 1000; the API default is 50
    # @return [DomainInfo]
    def lookup_domain(domain, limit: nil)
      raise TypeError, "domain must be a String" unless domain.is_a?(String)
      raise ArgumentError, "invalid domain" if ["", ".", ".."].include?(domain)
      raise ArgumentError, "limit must be a positive Integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)

      json = @transport.json("GET", "/lookup/domain/#{escape_path(domain)}", policy: :rate_limit, query: { limit: }.compact)
      Model.decode(DomainInfo, json)
    end

    # Returns the account that owns the API key, including its remaining
    # lookup credits. Free.
    #
    # @return [Account]
    def account
      Model.decode(Account, @transport.json("GET", "/account/me", policy: :transient))
    end

    # Checks that the API is up. An unhealthy API raises APIError and is not
    # retried, since a 503 is the answer.
    #
    # @return [nil]
    def health
      @transport.json("GET", "/health", policy: :rate_limit)
      nil
    end

    # Closes idle connections. Idempotent. Requests after close raise IOError.
    #
    # @return [nil]
    def close
      @transport.close
    end

    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect}>"
    end

    private

    def canonical_ip(ip)
      if ip.is_a?(IPAddr)
        raise ArgumentError, "IP address must not have a prefix" unless ip.prefix == (ip.ipv4? ? 32 : 128)

        ip = ip.to_s
      end
      raise TypeError, "IP address must be a String or IPAddr" unless ip.is_a?(String)
      raise ArgumentError, "invalid IP address" if ip.include?("/") || ip.include?("%")

      IPAddr.new(ip).to_s
    rescue IPAddr::InvalidAddressError
      raise ArgumentError, "invalid IP address"
    end

    def escape_path(value)
      value.b.gsub(/[^A-Za-z0-9\-._~$&+:=@]/n) { |char| format("%%%02X", char.ord) }
    end
  end
end
