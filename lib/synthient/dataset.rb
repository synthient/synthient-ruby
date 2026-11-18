# frozen_string_literal: true

module Synthient
  # A Synthient dataset: daily exports with no stream and no hourly exports.
  # Access datasets through the client, such as Client#geolocation.
  #
  # An export is identified by "latest", the newest day, or a UTC day as a
  # Date or "YYYY-MM-DD". Export#id values can be passed as they are.
  #
  # Each day has one file per format. Geolocation has ExportFormat::PARQUET,
  # the default, ExportFormat::CSV, gzip-compressed, and ExportFormat::MMDB, a
  # MaxMind DB. WHOIS has only ExportFormat::TAR_GZ, an archive of parquet
  # files that ExportMeta#entities describes. Requests for a day that isn't
  # published yet, or has no file in the requested format, raise a 404
  # APIError.
  class Dataset
    include ExportRequests

    # @api private
    def initialize(transport, path)
      @transport = transport
      @path = path
    end

    # Returns one page of the dataset's exports, newest first.
    #
    # @param limit [Integer, nil] exports per page; the API defaults to 100 and clamps values above 500
    # @param cursor [String, nil] the +next_cursor+ of the previous page
    # @param day [String, Date, nil] lists only this UTC day's export
    # @return [ExportPage]
    def list_exports(limit: nil, cursor: nil, day: nil)
      list_page(limit, cursor, day, {})
    end

    # Yields every export, newest first, fetching pages as they are needed.
    # Breaking out of the block stops fetching. Without a block, returns an
    # Enumerator.
    #
    # @param limit [Integer, nil] exports per page
    # @param cursor [String, nil] a +next_cursor+ to resume from
    # @param day [String, Date, nil] yields only this UTC day's export
    # @yieldparam export [Export]
    # @return [nil]
    # @raise [Error] if the API returns a cursor it already returned
    def each_export(limit: nil, cursor: nil, day: nil, &block)
      return enum_for(:each_export, limit:, cursor:, day:) unless block

      each_listed_export(cursor, block) { |next_cursor| list_exports(limit:, cursor: next_cursor, day:) }
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

    # Returns an export's metadata. Its +checksum+ and +size+ describe the
    # file in +format+, and +formats+ lists every file of the day.
    #
    # @param export [String, Date]
    # @param format [String, nil] an ExportFormat; by default parquet for
    #   geolocation and tar.gz for WHOIS
    # @return [ExportMeta]
    def export_meta(export, format: nil)
      meta(export_path(export, hourly: false), { format: })
    end

    # Returns a presigned URL for downloading an export. The URL is valid for
    # 24 hours and grants access without an API key, so treat it as a secret.
    #
    # @param export [String, Date]
    # @param format [String, nil] an ExportFormat
    # @return [URI::HTTP]
    def download_url(export, format: nil)
      location(export_path(export, hourly: false), { format: })
    end

    # Downloads an export, yielding the file's bytes in chunks as they arrive,
    # exactly as stored: a csv file stays gzip-compressed and a tar.gz stays
    # packed. The SDK does not verify them: compare a SHA-256 of the bytes
    # with the matching ExportFile#checksum. Breaking out of the block closes
    # the connection. Without a block, returns an Enumerator.
    #
    # @param export [String, Date]
    # @param format [String, nil] an ExportFormat
    # @yieldparam chunk [String] binary bytes
    # @return [nil]
    def download(export, format: nil, &)
      return enum_for(:download, export, format:) unless block_given?

      @transport.download(download_url(export, format:), &)
      nil
    end
  end
end
