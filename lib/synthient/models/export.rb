# frozen_string_literal: true

module Synthient
  module ExportKind
    HOURLY = "hourly"
    DAILY = "daily"
  end

  # File formats of exports. Feeds publish only parquet. New values may be
  # added.
  module ExportFormat
    PARQUET = "parquet"
    CSV = "csv"
    MMDB = "mmdb"
    TAR_GZ = "tar.gz"
  end

  # LITE is the export deduplicated to the latest row in its hour or day.
  module ExportVariant
    FULL = "full"
    LITE = "lite"
  end

  # The parquet files inside a WHOIS archive. New values may be added.
  module WhoisEntity
    ASNS = "asns"
    NETWORKS = "networks"
    ORGANISATIONS = "organisations"
    CONTACTS = "contacts"
    MAINTAINERS = "maintainers"
    TRANSFERS = "transfers"
    DELEGATIONS = "delegations"
  end

  # New values may be added, and the datasets already send others, such as
  # "double", "date", and "list<string>".
  module ParquetType
    STRING = "string"
    INT64 = "int64"
    UINT32 = "uint32"
    UINT64 = "uint64"
    BOOL = "bool"
    BYTES = "bytes"
  end

  # One file of an export. +format+ is one of ExportFormat, and +checksum+ is
  # the hex SHA-256 of the file as downloaded, so of the .csv.gz for csv.
  ExportFile = Model.define do
    required :format, :string
    required :size_bytes, :integer
    required :checksum, :string
  end

  # +type+ is one of ParquetType.
  ParquetColumn = Model.define do
    required :name, :string
    required :type, :string
  end

  # +fields+ is empty for an archive such as WHOIS.
  ParquetSchema = Model.define do
    # The WHOIS meta sent "fields": null on 2026-11-17.
    required :fields, [ParquetColumn], null_as: []
  end

  # One parquet file inside a WHOIS archive. +entity+ is one of WhoisEntity,
  # and +checksum+ is the hex SHA-256 of the parquet. +schema+ is set only by
  # export metadata.
  ExportEntity = Model.define do
    required :entity, :string
    required :row_count, :integer
    required :size_bytes, :integer
    required :checksum, :string
    optional :schema, ParquetSchema
  end

  # +hour+ is nil for a daily export. +formats+ lists every file of the
  # export, its own format first, and +size_bytes+ and +checksum+, the hex
  # SHA-256, describe that first file. +download_path+ includes the /api/v4
  # prefix. +entities+ is set only for WHOIS. +variant+ is
  # ExportVariant::LITE on a lite listing and nil otherwise.
  Export = Model.define do
    required :id, :string
    required :kind, :string
    required :date, :date
    optional :hour, :integer
    required :size_bytes, :integer
    required :row_count, :integer
    required :checksum, :string
    required :created_at, :unix_time
    required :download_path, :string
    required :formats, [ExportFile]
    optional :entities, [ExportEntity]
    optional :variant, :string
  end

  # +next_cursor+ is nil on the last page.
  ExportPage = Model.define do
    required :stream, :string
    required :exports, [Export], wire: "feeds"
    optional :next_cursor, :string
  end

  # +hour+ is nil for a daily export. +format+ is the ExportFormat that
  # +size+, in bytes, and +checksum+, the hex SHA-256, describe. +formats+
  # lists every file of the export, its own format first. A WHOIS meta has
  # an empty +schema+ and describes each parquet in +entities+. +variant+ is
  # ExportVariant::LITE for a lite export and nil otherwise.
  ExportMeta = Model.define do
    required :id, :string
    required :stream, :string
    required :kind, :string
    required :format, :string
    required :date, :unix_time
    optional :hour, :integer
    required :rows, :integer
    required :size, :integer
    required :checksum, :string
    required :created_at, :unix_time
    required :schema, ParquetSchema
    required :formats, [ExportFile]
    optional :entities, [ExportEntity]
    optional :variant, :string
  end

  # The rows and bytes exported on one UTC day. +kind+ is ExportKind::DAILY
  # when the day's daily export is the total, or ExportKind::HOURLY when its
  # hourly exports were summed, as for today. +snapshots+ is the number of
  # files counted.
  ExportVolumeDay = Model.define do
    required :date, :date
    required :kind, :string
    required :snapshots, :integer
    required :row_count, :integer
    required :size_bytes, :integer
  end

  # +days+ runs oldest first and leaves out days without exports.
  ExportVolume = Model.define do
    required :stream, :string
    required :days, [ExportVolumeDay]
  end
end
