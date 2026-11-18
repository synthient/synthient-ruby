# frozen_string_literal: true

module Synthient
  # The export requests that Feed and Dataset share. +options+ holds Feed's
  # +variant+ or Dataset's +format+.
  module ExportRequests
    private

    def list_page(limit, cursor, day, options)
      raise ArgumentError, "limit must be a positive Integer" unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      raise TypeError, "cursor must be a String" unless cursor.nil? || cursor.is_a?(String)

      day = day.strftime("%Y-%m-%d") if day.instance_of?(Date)
      raise TypeError, "day must be a String or Date" unless day.nil? || day.is_a?(String)
      unless day.nil? || (day.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.valid_date?(*day.split("-").map(&:to_i)))
        raise ArgumentError, "invalid day #{day.inspect}"
      end

      query = { limit:, cursor:, day: }.reject { |_, value| value.nil? || value == "" }.merge(option_query(options))
      Model.decode(ExportPage, @transport.json("GET", "#{@path}/export", policy: :transient, query:))
    end

    def each_listed_export(cursor, block)
      seen = Set.new
      while seen.add?(cursor)
        page = yield cursor
        page.exports.each(&block)
        cursor = page.next_cursor
        return if cursor.nil? || cursor.empty?
      end
      raise Error, "export listing returned a repeated cursor"
    end

    def volume(days)
      raise ArgumentError, "days must be a positive Integer" unless days.nil? || (days.is_a?(Integer) && days.positive?)

      json = @transport.json("GET", "#{@path}/export/daily", policy: :transient, query: { days: }.compact)
      Model.decode(ExportVolume, json)
    end

    def meta(id, options)
      json = @transport.json("GET", "#{@path}/export/#{id}/meta", policy: :transient, query: option_query(options))
      Model.decode(ExportMeta, json)
    end

    def location(id, options)
      @transport.redirect_location("#{@path}/export/#{id}", query: option_query(options))
    end

    def option_query(options)
      options.each { |name, value| raise TypeError, "#{name} must be a String" unless value.nil? || value.is_a?(String) }
      options.reject { |_, value| value.nil? || value == "" }
    end

    def export_path(export, hourly:)
      case export
      when Time
        raise TypeError, "export must be a String or Date, because datasets have no hourly exports" unless hourly

        time = export.getutc
        "#{time.strftime("%Y-%m-%d")}/#{time.hour}"
      when DateTime
        raise TypeError, "export must be a #{hourly ? "Time" : "String"} or Date, not a DateTime"
      when Date
        export.strftime("%Y-%m-%d")
      when String
        return export if export == "latest"

        match = %r{\A(\d{4})-(\d{2})-(\d{2})(?:/(\d{1,2}))?\z}.match(export)
        unless match && Date.valid_date?(match[1].to_i, match[2].to_i, match[3].to_i) && match[4].to_i <= 23
          raise ArgumentError, "invalid export ID #{export.inspect}"
        end
        raise ArgumentError, "invalid export ID #{export.inspect}: datasets have no hourly exports" if match[4] && !hourly

        match[4] ? "#{match[1]}-#{match[2]}-#{match[3]}/#{match[4].to_i}" : export
      else
        raise TypeError, hourly ? "export must be a String, Date, or Time" : "export must be a String or Date"
      end
    end
  end
  private_constant :ExportRequests
end
