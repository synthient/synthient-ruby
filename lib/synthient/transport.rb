# frozen_string_literal: true

module Synthient
  # Sends requests to the API and to export storage over Net::HTTP.
  #
  # Net::HTTP's own retry is disabled on every session, so a stale keep-alive
  # connection never replays a billed lookup. Retries happen only here, under
  # one of two policies: :transient retries rate limits, 5xx responses, and
  # failures before a response arrives; :rate_limit retries only a 429 that
  # carries Retry-After, which the API sends before doing any billed work.
  #
  # @api private
  class Transport
    MAX_RESPONSE_SIZE = 16 << 20
    MAX_ERROR_SIZE = 64 << 10
    MAX_EVENT_SIZE = 16 << 20
    MAX_IDLE_SESSIONS = 8
    MAX_RETRY_AFTER = 60
    MAX_REDIRECTS = 10
    RETRY_STATUSES = %w[500 502 503 504].freeze
    RETRY = Object.new.freeze
    REDIRECT = Object.new.freeze
    private_constant :RETRY, :REDIRECT
    TRANSPORT_ERRORS = [
      IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError,
      Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    ].freeze

    # Parses a Retry-After value into seconds: delta seconds clamped to
    # [0, 2**31], or an HTTP date, where a past date is 0. Returns nil when
    # the value is absent or invalid.
    def self.parse_retry_after(value)
      value = value.to_s.strip
      return nil if value.empty?
      return value.to_i.clamp(0, 2**31) if value.match?(/\A[-+]?\d+\z/)

      [Time.httpdate(value) - Time.now, 0].max
    rescue ArgumentError
      nil
    end

    def initialize(base_url:, api_key:, user_agent:, max_retries:, timeout:, open_timeout:, response_hook:)
      @base_url = base_url
      @base_scheme = URI(base_url).scheme
      @api_key = api_key
      @user_agent = user_agent
      @max_retries = max_retries
      @timeout = timeout
      @open_timeout = open_timeout
      @response_hook = response_hook
      @idle = []
      @mutex = Mutex.new
      @pid = Process.pid
      @closed = false
    end

    # Sends an API request and returns the JSON object of a 2xx response.
    def json(method, path, policy:, query: nil, body: nil)
      execute(method, path, policy:, query:, body:) do |response|
        raise_api_error(response) unless response.is_a?(Net::HTTPSuccess)

        data = "".b
        read_body(response) do |chunk|
          data << chunk
          raise DecodeError, "response body exceeds #{MAX_RESPONSE_SIZE} bytes" if data.bytesize > MAX_RESPONSE_SIZE
        end
        parse_object(data)
      end
    end

    # Opens an NDJSON stream and yields each event as a JSON object. Blank
    # keepalive lines are skipped, and a final line without a newline is
    # still decoded.
    def stream(path)
      execute("GET", path, policy: :transient, accept: "application/x-ndjson", dedicated: true) do |response|
        raise_api_error(response) unless response.code == "200"

        pending = "".b
        read_body(response) do |chunk|
          pending << chunk
          while (newline = pending.index("\n"))
            line = pending.slice!(0, newline + 1)
            raise DecodeError, "stream event exceeds #{MAX_EVENT_SIZE} bytes" if line.bytesize > MAX_EVENT_SIZE

            line.strip!
            yield parse_object(line) unless line.empty?
          end
          raise DecodeError, "stream event exceeds #{MAX_EVENT_SIZE} bytes" if pending.bytesize > MAX_EVENT_SIZE
        end
        pending.strip!
        yield parse_object(pending) unless pending.empty?
      end
    end

    # Returns the validated Location of the redirect an export answers with.
    def redirect_location(path)
      execute("GET", path, policy: :transient) do |response|
        raise_api_error(response) if response.code.to_i >= 400
        unless response.is_a?(Net::HTTPRedirection)
          raise DecodeError, "expected a redirect to the export, got status #{response.code}"
        end

        location = resolve_location(response)
        raise DecodeError, "export redirect has no valid location" unless location
        raise DecodeError, "export redirect does not use https" unless ["https", @base_scheme].include?(location.scheme)

        size = 0
        read_body(response) do |chunk|
          size += chunk.bytesize
          raise DecodeError, "export redirect body exceeds #{MAX_ERROR_SIZE} bytes" if size > MAX_ERROR_SIZE
        end
        location
      end
    end

    # Downloads a presigned export URL from storage and yields its bytes as
    # stored. Only a User-Agent header is sent: never the API key. Up to
    # MAX_REDIRECTS redirects are followed, and never from https to http.
    def download(uri, &block)
      redirects = 0
      while redirects <= MAX_REDIRECTS
        session = nil
        response = nil
        next_uri = catch(REDIRECT) do
          session = start_session(uri)
          request = Net::HTTP::Get.new(uri, "User-Agent" => @user_agent, "Accept-Encoding" => "identity")
          session.request(request) do |res|
            response = res
            if res.is_a?(Net::HTTPRedirection)
              throw REDIRECT, resolve_location(res) || raise(Error, "export redirect has no valid location")
            end
            raise_api_error(res) unless res.code == "200"

            read_body(res, &block)
          end
          return
        rescue *TRANSPORT_ERRORS => e
          raise unless response.nil?

          raise connection_error(e)
        ensure
          discard(session)
        end
        raise Error, "export redirect downgrades to http" if uri.scheme == "https" && next_uri.scheme == "http"

        redirects += 1
        uri = next_uri
      end
      raise Error, "too many export redirects"
    end

    # Closes idle connections. Requests after close raise IOError.
    def close
      sessions = @mutex.synchronize do
        @closed = true
        @pid == Process.pid ? @idle.slice!(0..) : []
      end
      sessions.each { |session| discard(session) }
      nil
    end

    def inspect
      "#<#{self.class.name} #{@base_url}>"
    end

    private

    def execute(method, path, policy:, query: nil, body: nil, accept: "application/json", dedicated: false, &)
      raise IOError, "client is closed" if @closed

      uri = URI("#{@base_url}#{path}#{"?#{URI.encode_www_form(query.sort)}" unless query.nil? || query.empty?}")
      (0..@max_retries).each do |attempt|
        delay = catch(RETRY) { return attempt_request(uri, method, body, accept, policy, attempt, dedicated, &) }
        sleep(delay)
      end
    end

    def attempt_request(uri, method, body, accept, policy, attempt, dedicated)
      response = nil
      reusable = false
      session = dedicated ? start_session(uri) : checkout(uri)
      headers = { "X-Api-Key" => @api_key, "User-Agent" => @user_agent, "Accept" => accept }
      headers["Content-Type"] = "application/json" if body
      result = nil
      session.request(Net::HTTPGenericRequest.new(method, !body.nil?, true, uri, headers), body) do |res|
        response = res
        report(res) if @response_hook
        retryable = if res.code == "429"
                      !res["retry-after"].to_s.strip.empty?
                    else
                      policy == :transient && RETRY_STATUSES.include?(res.code)
                    end
        retry_after = Transport.parse_retry_after(res["retry-after"])
        if retryable && attempt < @max_retries && (retry_after.nil? || retry_after <= MAX_RETRY_AFTER)
          throw RETRY, [backoff(attempt), retry_after || 0].max
        end

        result = yield res
      end
      reusable = !dedicated
      result
    rescue *TRANSPORT_ERRORS => e
      raise unless response.nil?

      throw RETRY, backoff(attempt) if policy == :transient && attempt < @max_retries && !e.is_a?(OpenSSL::SSL::SSLError)

      raise connection_error(e)
    ensure
      reusable ? checkin(session) : discard(session)
    end

    def backoff(attempt)
      [2**[attempt, 5].min, 30].min * (0.75 + (rand / 2))
    end

    def report(response)
      headers = response.each_header.to_h { |name, value| [name.freeze, value.freeze] }.freeze
      limits = %w[ratelimit-limit ratelimit-remaining ratelimit-reset].map { |name| response[name]&.strip }
      if limits.all? { |value| value&.match?(/\A\d+\z/) }
        limit, remaining, reset = limits.map(&:to_i)
        rate_limit = RateLimit.new(limit:, remaining:, reset: [reset, 2**31].min)
      end
      @response_hook.call(
        ResponseMetadata.new(status: response.code.to_i, request_id: response["x-request-id"], rate_limit:, headers:)
      )
    end

    # Reads a response body in chunks, turning transport failures into
    # ConnectionError. Exceptions raised by the block pass through unchanged.
    def read_body(response)
      in_block = false
      response.read_body do |chunk|
        in_block = true
        yield chunk
        in_block = false
      end
    rescue *TRANSPORT_ERRORS => e
      raise if in_block

      raise connection_error(e)
    rescue Zlib::Error
      raise if in_block

      raise DecodeError, "response body has invalid compression"
    end

    def connection_error(error)
      timeout = error.is_a?(Timeout::Error) || error.is_a?(Errno::ETIMEDOUT)
      (timeout ? TimeoutError : ConnectionError).new(error.message)
    end

    def parse_object(json)
      object = JSON.parse(json, freeze: true)
      raise DecodeError, "response is not a JSON object" unless object.is_a?(Hash)

      object
    rescue JSON::ParserError
      raise DecodeError, "response is not valid JSON"
    end

    # Raises an APIError for an error response, parsing up to MAX_ERROR_SIZE
    # bytes of problem details. A text/plain body becomes the detail.
    def raise_api_error(response)
      status = response.code.to_i
      retry_after = Transport.parse_retry_after(response["retry-after"])
      request_id = response["x-request-id"]
      data = "".b
      begin
        read_body(response) do |chunk|
          data << chunk
          break if data.bytesize >= MAX_ERROR_SIZE
        end
      rescue ConnectionError
        raise APIError.new(status:, request_id:, retry_after:)
      end

      problem = begin
        JSON.parse(data, freeze: true)
      rescue JSON::ParserError
        nil
      end
      fields = {}
      if problem.is_a?(Hash)
        %w[type title detail].each { |key| fields[key.to_sym] = problem[key] if problem[key].is_a?(String) }
        errors = problem["errors"]
        if errors.is_a?(Hash) && errors.each_value.all? { |messages| messages.is_a?(Array) && messages.all?(String) }
          fields[:errors] = errors
        end
        request_id = problem["instance"] if (request_id.nil? || request_id.empty?) && problem["instance"].is_a?(String)
      elsif response.content_type == "text/plain"
        fields[:detail] = data.force_encoding(Encoding::UTF_8).scrub.strip
      end
      raise APIError.new(status:, request_id:, retry_after:, **fields)
    end

    def resolve_location(response)
      location = response["location"].to_s.strip
      return nil if location.empty?

      uri = URI.join(response.uri.to_s, location)
      uri if uri.is_a?(URI::HTTP) && !uri.host.to_s.empty? && uri.userinfo.nil?
    rescue URI::Error
      nil
    end

    def checkout(uri)
      session = @mutex.synchronize do
        if @pid != Process.pid
          @idle.clear
          @pid = Process.pid
        end
        @idle.pop
      end
      session || start_session(uri)
    end

    def checkin(session)
      kept = @mutex.synchronize do
        next false if @closed || @pid != Process.pid || @idle.size >= MAX_IDLE_SESSIONS

        @idle.push(session)
      end
      discard(session) unless kept
    end

    def discard(session)
      session.finish if session&.started?
    rescue IOError
      nil
    end

    def start_session(uri)
      session = Net::HTTP.new(uri.hostname, uri.port)
      session.use_ssl = uri.scheme == "https"
      session.verify_mode = OpenSSL::SSL::VERIFY_PEER
      session.verify_hostname = true
      session.open_timeout = @open_timeout
      session.read_timeout = @timeout
      session.write_timeout = @timeout
      session.keep_alive_timeout = 2
      session.max_retries = 0
      session.ignore_eof = false
      session.response_body_encoding = false
      session.set_debug_output(nil)
      session.start
    end
  end
end
