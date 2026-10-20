# frozen_string_literal: true

module Synthient
  module ExportKind
    HOURLY = "hourly"
    DAILY = "daily"
  end

  # New values may be added.
  module ParquetType
    STRING = "string"
    INT64 = "int64"
    UINT32 = "uint32"
    UINT64 = "uint64"
    BOOL = "bool"
    BYTES = "bytes"
  end

  # +hour+ is nil for a daily export. +checksum+ is the hex SHA-256 of the
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

  # +next_cursor+ is nil on the last page.
  ExportPage = Model.define do
    required :stream, :string
    required :exports, [Export], wire: "feeds"
    optional :next_cursor, :string
  end

  # +type+ is one of ParquetType.
  ParquetColumn = Model.define do
    required :name, :string
    required :type, :string
  end

  ParquetSchema = Model.define do
    required :fields, [ParquetColumn]
  end

  # +hour+ is nil for a daily export. +size+ is in bytes and +checksum+ is
  # the hex SHA-256 of the file.
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
