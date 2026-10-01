# frozen_string_literal: true

module Synthient
  # The base class of every error the SDK raises for a failed request.
  # Invalid arguments raise ArgumentError or TypeError instead.
  class Error < StandardError; end

  # The request could not be sent, or the response could not be read. The
  # underlying exception is available as +cause+.
  class ConnectionError < Error; end

  # Connecting, sending, or waiting for response data took longer than the
  # client's timeout.
  class TimeoutError < ConnectionError; end

  # A successful response did not match the API schema.
  class DecodeError < Error; end

  # The API, or export storage, answered with an error status.
  #
  # The message holds only the status, such as "429 Too Many Requests", so it
  # is safe to log. The problem details the API sent are available as
  # attributes.
  class APIError < Error
    STATUS_TEXT = {
      300 => "Multiple Choices", 301 => "Moved Permanently", 302 => "Found", 303 => "See Other",
      304 => "Not Modified", 307 => "Temporary Redirect", 308 => "Permanent Redirect",
      400 => "Bad Request", 401 => "Unauthorized", 402 => "Payment Required", 403 => "Forbidden",
      404 => "Not Found", 405 => "Method Not Allowed", 406 => "Not Acceptable", 408 => "Request Timeout",
      409 => "Conflict", 410 => "Gone", 413 => "Request Entity Too Large", 415 => "Unsupported Media Type",
      422 => "Unprocessable Entity", 429 => "Too Many Requests", 500 => "Internal Server Error",
      501 => "Not Implemented", 502 => "Bad Gateway", 503 => "Service Unavailable", 504 => "Gateway Timeout"
    }.freeze

    # @return [Integer] the HTTP status code
    attr_reader :status
    # @return [String, nil] the problem type URI
    attr_reader :type
    # @return [String, nil] a short summary of the problem
    attr_reader :title
    # @return [String, nil] an explanation of this occurrence of the problem
    attr_reader :detail
    # @return [Hash{String => Array<String>}] validation errors by field, from a 422
    attr_reader :errors
    # @return [String, nil] the X-Request-Id of the response, for support requests
    attr_reader :request_id
    # @return [Numeric, nil] seconds the server asked to wait before retrying
    attr_reader :retry_after

    def initialize(status:, type: nil, title: nil, detail: nil, errors: {}, request_id: nil, retry_after: nil)
      @status = status
      @type = type
      @title = title
      @detail = detail
      @errors = errors
      @request_id = request_id
      @retry_after = retry_after
      super([status, STATUS_TEXT[status]].compact.join(" "))
    end
  end
end
