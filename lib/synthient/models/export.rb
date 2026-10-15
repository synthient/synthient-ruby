# frozen_string_literal: true

module Synthient
  # Whether an export covers an hour or a day.
  module ExportKind
    HOURLY = "hourly"
    DAILY = "daily"
  end

  # Parquet column types. New values may be added.
  module ParquetType
    STRING = "string"
    INT64 = "int64"
    UINT32 = "uint32"
    UINT64 = "uint64"
    BOOL = "bool"
    BYTES = "bytes"
  end

  # A parquet export of a feed. +id+ can be passed to the Feed methods as it
  # is. +hour+ is nil for a daily export. +checksum+ is the hex SHA-256 of the
  # file. +download_path+ includes the /api/v4 prefix.
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
  end

  # One page of a feed's exports. +next_cursor+ is nil on the last page.
  ExportPage = Model.define do
    required :stream, :string
    required :exports, [Export], wire: "feeds"
    optional :next_cursor, :string
  end

  # A parquet column. +type+ is one of ParquetType.
  ParquetColumn = Model.define do
    required :name, :string
    required :type, :string
  end

  # The columns of a parquet export.
  ParquetSchema = Model.define do
    required :fields, [ParquetColumn]
  end

  # The metadata of a parquet export. +hour+ is nil for a daily export.
  # +size+ is in bytes and +checksum+ is the hex SHA-256 of the file.
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
  end
end
