# frozen_string_literal: true

module Synthient
  # A Synthient data feed: a real-time stream of events and hourly parquet
  # exports that roll up into daily exports. Access feeds through the client,
  # such as Client#proxies.
  #
  # An export is identified by "latest", a UTC day as a Date or
  # "YYYY-MM-DD", or a UTC hour as a Time or "YYYY-MM-DD/H", where a
  # zero-padded hour is also accepted. Export#id values can be passed as they
  # are. "latest" is the newest hourly export during the day, or the daily
  # export once that day's hours are rolled up.
  #
  # An hourly export is available until its day's daily export is rolled up,
  # shortly after 00:30 UTC the next day. After that, requests for the hour
  # raise a 400 APIError. While a daily export is being rolled up, requests
  # for it raise a 404 APIError with +retry_after+ set.
  #
  # The proxies, anonymizers, and JA4T feeds also publish a lite variant of
  # each export, deduplicated to the latest row in its hour or day: one row
  # per address and provider for proxies, per address, fingerprint, and
  # provider for JA4T, and per range and provider for anonymizers. Pass
  # +variant: ExportVariant::LITE+ to reach it. A lite file is published
  # shortly after its export, and until then requests for it raise a 404
  # APIError. Other feeds have no lite variant, so their lite listings are
  # empty.
  class Feed
    include ExportRequests

    # @api private
    def initialize(transport, path, event_type)
      @transport = transport
      @path = path
      @event_type = event_type
    end

    # Needs the feed's stream scope, such as PROXY_FIREHOSE.
    #
    # The server can end a stream at any time, such as during a deploy, and
    # the call then returns normally. Events sent while disconnected are
    # missed, so reconnect in a loop. Breaking out of the block closes the
    # connection. Without a block, returns an Enumerator that opens the
    # connection when iterated.
    #
    # @yieldparam event [Object] an event of this feed's type
    # @return [nil]
    def stream
      return enum_for(:stream) unless block_given?

      @transport.stream("#{@path}/stream") { |object| yield Model.decode(@event_type, object) }
      nil
    end

    # Returns one page of the feed's exports, newest first.
    #
    # @param limit [Integer, nil] exports per page; the API defaults to 100 and clamps values above 500
    # @param cursor [String, nil] the +next_cursor+ of the previous page
    # @param day [String, Date, nil] lists only this UTC day's exports
    # @param variant [String, nil] an ExportVariant. A lite export's ID is the
    #   same as the full one's, so pass the variant again to reach its file.
    # @return [ExportPage]
    def list_exports(limit: nil, cursor: nil, day: nil, variant: nil)
      list_page(limit, cursor, day, { variant: })
    end

    # Yields every export, newest first, fetching pages as they are needed.
    # Breaking out of the block stops fetching. Without a block, returns an
    # Enumerator.
    #
    # @param limit [Integer, nil] exports per page
    # @param cursor [String, nil] a +next_cursor+ to resume from
    # @param day [String, Date, nil] yields only this UTC day's exports
    # @param variant [String, nil] an ExportVariant
    # @yieldparam export [Export]
    # @return [nil]
    # @raise [Error] if the API returns a cursor it already returned
    def each_export(limit: nil, cursor: nil, day: nil, variant: nil, &block)
      return enum_for(:each_export, limit:, cursor:, day:, variant:) unless block

      each_listed_export(cursor, block) { |next_cursor| list_exports(limit:, cursor: next_cursor, day:, variant:) }
      nil
    end

    # Returns the rows and bytes exported on each UTC day of a window that
    # ends today, oldest first. Today's totals are still growing.
    #
    # @param days [Integer, nil] the window's length; the API defaults to 90 and allows up to 366
    # @return [ExportVolume]
    def export_volume(days: nil)
      volume(days)
    end

    # Returns an export's metadata, including its parquet schema.
    #
    # @param export [String, Date, Time]
    # @param variant [String, nil] an ExportVariant
    # @return [ExportMeta]
    def export_meta(export, variant: nil)
      meta(export_path(export, hourly: true), { variant: })
    end

    # Returns a presigned URL for downloading an export. The URL is valid for
    # 24 hours and grants access without an API key, so treat it as a secret.
    #
    # @param export [String, Date, Time]
    # @param variant [String, nil] an ExportVariant
    # @return [URI::HTTP]
    def download_url(export, variant: nil)
      location(export_path(export, hourly: true), { variant: })
    end

    # Downloads an export, yielding the parquet file's bytes in chunks as they
    # arrive. The SDK does not verify them: compare a SHA-256 of the bytes
    # with Export#checksum or ExportMeta#checksum. Breaking out of the block
    # closes the connection. Without a block, returns an Enumerator.
    #
    # @param export [String, Date, Time]
    # @param variant [String, nil] an ExportVariant
    # @yieldparam chunk [String] binary bytes
    # @return [nil]
    def download(export, variant: nil, &)
      return enum_for(:download, export, variant:) unless block_given?

      @transport.download(download_url(export, variant:), &)
      nil
    end
  end
end
