# frozen_string_literal: true

module Synthient
  # The rate limit state reported in a response's RateLimit-* headers. +reset+
  # is the number of seconds until the window resets.
  RateLimit = Data.define(:limit, :remaining, :reset)

  # Describes one API response. A client's +response_hook+ receives one for
  # every response from the API, including retried attempts, export pages,
  # stream handshakes, and responses that later fail to decode. Export
  # downloads from storage are not reported.
  #
  # +headers+ is a frozen copy with lowercase names. +rate_limit+ is nil
  # unless all three RateLimit-* headers are present and valid.
  ResponseMetadata = Data.define(:status, :request_id, :rate_limit, :headers)
end
