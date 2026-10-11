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
  class Feed
    # @api private
    def initialize(transport, path, event_type)
      @transport = transport
      @path = path
      @event_type = event_type
    end

    # Streams events as they happen, yielding each decoded event. Needs the
    # feed's stream scope, such as PROXY_FIREHOSE.
    #
    # There is no resume: events sent while disconnected are missed. The
    # server ends each stream after about 30 minutes, and the call then
    # returns normally, so reconnect in a loop. Breaking out of the block
    # closes the connection. Without a block, returns an Enumerator that opens
    # the connection when iterated.
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
    # @param limit [Integer, nil] exports per page, 1 to 500; the API default is 100
    # @param cursor [String, nil] the +next_cursor+ of the previous page
    # @return [ExportPage]
    def list_exports(limit: nil, cursor: nil)
      raise ArgumentError, "limit must be a positive Integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      raise TypeError, "cursor must be a String" unless cursor.nil? || cursor.is_a?(String)

      query = { limit:, cursor: }.reject { |_, value| value.nil? || value == "" }
      Model.decode(ExportPage, @transport.json("GET", "#{@path}/export", policy: :transient, query:))
    end

    # Yields every export, newest first, fetching pages as they are needed.
    # Breaking out of the block stops fetching. Without a block, returns an
    # Enumerator.
    #
    # @param limit [Integer, nil] exports per page
    # @param cursor [String, nil] the cursor to start from
    # @yieldparam export [Export]
    # @return [nil]
    # @raise [Error] if the API returns a cursor it already returned
    def each_export(limit: nil, cursor: nil, &block)
      return enum_for(:each_export, limit:, cursor:) unless block

      seen = Set.new
      seen << cursor unless cursor.nil? || cursor.empty?
      page = list_exports(limit:, cursor:)
      page.exports.each(&block)
      until (cursor = page.next_cursor).nil? || cursor.empty?
        raise Error, "export listing returned a repeated cursor" unless seen.add?(cursor)

        page = list_exports(limit:, cursor:)
        page.exports.each(&block)
      end
      nil
    end

    # Returns an export's metadata, including its parquet schema.
    #
    # @param export [String, Date, Time]
    # @return [ExportMeta]
    def export_meta(export)
      Model.decode(ExportMeta, @transport.json("GET", "#{@path}/export/#{export_path(export)}/meta", policy: :transient))
    end

    # Returns a presigned URL for downloading an export. The URL is valid for
    # 24 hours and grants access without an API key, so treat it as a secret.
    #
    # @param export [String, Date, Time]
    # @return [URI::HTTP]
    def download_url(export)
      @transport.redirect_location("#{@path}/export/#{export_path(export)}")
    end

    # Downloads an export, yielding the parquet file's bytes in chunks as they
    # arrive. The SDK does not verify them: compare a SHA-256 of the bytes
    # with Export#checksum or ExportMeta#checksum. Breaking out of the block
    # closes the connection. Without a block, returns an Enumerator.
    #
    # @param export [String, Date, Time]
    # @yieldparam chunk [String] binary bytes
    # @return [nil]
    def download(export, &)
      return enum_for(:download, export) unless block_given?

      @transport.download(download_url(export), &)
      nil
    end

    private

    def export_path(export)
      case export
      when Time
        time = export.getutc
        "#{time.strftime("%Y-%m-%d")}/#{time.hour}"
      when DateTime
        raise TypeError, "export must be a Time or Date, not a DateTime"
      when Date
        export.strftime("%Y-%m-%d")
      when String
        return export if export == "latest"

        match = %r{\A(\d{4})-(\d{2})-(\d{2})(?:/(\d{1,2}))?\z}.match(export)
        unless match && Date.valid_date?(match[1].to_i, match[2].to_i, match[3].to_i) && match[4].to_i <= 23
          raise ArgumentError, "invalid export ID #{export.inspect}"
        end

        match[4] ? "#{match[1]}-#{match[2]}-#{match[3]}/#{match[4].to_i}" : export
      else
        raise TypeError, "export must be a String, Date, or Time"
      end
    end
  end
end
