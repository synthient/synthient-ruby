# frozen_string_literal: true

require_relative "test_helper"

class FeedTest < SynthientTest
  META = {
    "id" => "2026-05-07", "stream" => "proxies", "kind" => "daily", "format" => "parquet", "date" => 1_778_112_000,
    "rows" => 1200, "size" => 1_048_576, "checksum" => "ab12", "created_at" => 1_778_187_600,
    "schema" => { "fields" => [{ "name" => "ip", "type" => "string" }, { "name" => "asn", "type" => "uint32" }] },
    "formats" => [{ "format" => "parquet", "size_bytes" => 1_048_576, "checksum" => "ab12" }]
  }.freeze

  FEEDS = {
    proxies: "proxies", anonymizers: "anonymizers", torrents: "torrents", ja4t: "ja4t",
    helios_http: "helios/http", helios_https: "helios/https", helios_dns: "helios/dns", helios_adb: "helios/adb"
  }.freeze

  VOLUME = {
    "stream" => "proxies",
    "days" => [
      { "date" => "2026-11-16", "kind" => "daily", "snapshots" => 1, "row_count" => 1_440_452_210,
        "size_bytes" => 19_629_681_638 },
      { "date" => "2026-11-17", "kind" => "hourly", "snapshots" => 3, "row_count" => 64_417_250,
        "size_bytes" => 880_000_000 }
    ]
  }.freeze

  def page(exports, next_cursor = nil)
    json(200, { "stream" => "proxies", "feeds" => exports, "next_cursor" => next_cursor }.compact)
  end

  def test_export_ids
    server = serve { json(200, META) }
    client = new_client(server)
    {
      "latest" => "latest",
      "2026-05-03" => "2026-05-03",
      "2026-05-03/7" => "2026-05-03/7",
      "2026-05-03/07" => "2026-05-03/7",
      "2026-05-03/00" => "2026-05-03/0",
      "2026-05-03/23" => "2026-05-03/23",
      Date.new(2026, 5, 3) => "2026-05-03",
      Time.new(2026, 5, 3, 22, 30, 0, "-05:00") => "2026-05-04/3"
    }.each do |export, path|
      client.proxies.export_meta(export)

      assert_equal "/api/v4/feeds/proxies/export/#{path}/meta", server.paths.last, export.inspect
    end
  end

  def test_invalid_export_ids_send_no_request
    server = serve { json(200, META) }
    client = new_client(server)
    ["", "latest/3", "2026-5-3", "2026-02-30", "2026-05-03/24", "2026-05-03/", "../account/me", "2026-05-03/07/meta",
     "2026-05-03/7 ", " 2026-05-03"].each do |export|
      assert_raises(ArgumentError, export.inspect) { client.proxies.export_meta(export) }
      assert_raises(ArgumentError, export.inspect) { client.proxies.download_url(export) }
    end
    [nil, 20_260_503, DateTime.new(2026, 5, 3)].each do |export|
      assert_raises(TypeError, export.inspect) { client.proxies.export_meta(export) }
    end
    assert_empty server.requests
  end

  def test_routes_for_every_feed
    server = serve { |request| request.path.include?("/daily") ? json(200, VOLUME) : json(200, META) }
    client = new_client(server)
    FEEDS.each do |feed, path|
      client.public_send(feed).export_meta("2026-05-03/7")

      assert_equal "/api/v4/feeds/#{path}/export/2026-05-03/7/meta", server.paths.last
      client.public_send(feed).export_volume

      assert_equal "/api/v4/feeds/#{path}/export/daily", server.paths.last
    end
  end

  def test_export_meta
    server = serve { json(200, META) }
    meta = new_client(server).proxies.export_meta("2026-05-07")

    assert_equal Synthient::ExportKind::DAILY, meta.kind
    assert_nil meta.hour
    assert_equal Time.at(1_778_112_000, in: "UTC"), meta.date
    assert_equal [Synthient::ParquetType::STRING, Synthient::ParquetType::UINT32], meta.schema.fields.map(&:type)
  end

  def test_list_exports
    server = serve { page([EXPORT, EXPORT.except("hour").merge("id" => "2026-05-06", "kind" => "daily")], "c2") }
    result = new_client(server).proxies.list_exports(limit: 2, cursor: "c1")

    assert_equal ["/api/v4/feeds/proxies/export?cursor=c1&limit=2"], server.paths
    assert_equal "c2", result.next_cursor
    hourly, daily = result.exports

    assert_equal Date.new(2026, 5, 7), hourly.date
    assert_equal 21, hourly.hour
    assert_nil daily.hour
    assert_equal Time.at(1_778_187_600, in: "UTC"), hourly.created_at
    assert_equal [Synthient::ExportFormat::PARQUET], hourly.formats.map(&:format)
    assert_nil hourly.entities
    assert_nil hourly.variant
  end

  def test_list_exports_validates_arguments
    server = serve { page([]) }
    client = new_client(server)

    [0, -1, 2.0, "2"].each { |limit| assert_raises(ArgumentError) { client.proxies.list_exports(limit:) } }
    assert_raises(TypeError) { client.proxies.list_exports(cursor: 5) }
    ["", "latest", "2026-5-7", "2026-02-30", "2026-05-07/7", " 2026-05-07"].each do |day|
      assert_raises(ArgumentError, day) { client.proxies.list_exports(day:) }
    end
    [20_260_507, Time.utc(2026, 5, 7), DateTime.new(2026, 5, 7)].each do |day|
      assert_raises(TypeError, day.inspect) { client.proxies.list_exports(day:) }
    end
    assert_raises(TypeError) { client.proxies.list_exports(variant: :lite) }
    client.proxies.list_exports(cursor: "")

    assert_equal ["/api/v4/feeds/proxies/export"], server.paths
  end

  def test_list_exports_day_and_variant
    server = serve { page([EXPORT.merge("variant" => "lite")]) }
    client = new_client(server)
    result = client.proxies.list_exports(limit: 5, day: "2026-05-07", variant: Synthient::ExportVariant::LITE)
    client.proxies.list_exports(day: Date.new(2026, 5, 7))

    assert_equal ["/api/v4/feeds/proxies/export?day=2026-05-07&limit=5&variant=lite",
                  "/api/v4/feeds/proxies/export?day=2026-05-07"], server.paths
    assert_equal Synthient::ExportVariant::LITE, result.exports.first.variant
  end

  def test_each_export_keeps_day_and_variant
    server = serve { |request| request.path.include?("cursor") ? page([EXPORT]) : page([EXPORT], "c1") }
    new_client(server).proxies.each_export(day: "2026-05-07", variant: "lite").to_a

    assert_equal ["/api/v4/feeds/proxies/export?day=2026-05-07&variant=lite",
                  "/api/v4/feeds/proxies/export?cursor=c1&day=2026-05-07&variant=lite"], server.paths
  end

  def test_variant_on_meta_and_download_url
    server = serve do |request|
      request.path.include?("/meta") ? json(200, META.merge("variant" => "lite")) : [307, { "location" => "/file" }, ""]
    end
    client = new_client(server)
    %w[2026-05-07 2026-05-07/7].each do |export|
      assert_equal "lite", client.proxies.export_meta(export, variant: "lite").variant
      client.proxies.download_url(export, variant: "lite")
    end
    client.proxies.export_meta("latest", variant: "")

    assert_equal ["/api/v4/feeds/proxies/export/2026-05-07/meta?variant=lite",
                  "/api/v4/feeds/proxies/export/2026-05-07?variant=lite",
                  "/api/v4/feeds/proxies/export/2026-05-07/7/meta?variant=lite",
                  "/api/v4/feeds/proxies/export/2026-05-07/7?variant=lite",
                  "/api/v4/feeds/proxies/export/latest/meta"], server.paths
    assert_raises(TypeError) { client.proxies.export_meta("latest", variant: :lite) }
  end

  def test_missing_lite_export_raises_api_error
    server = serve { problem(404, { "detail" => "No snapshot found for the requested date" }) }
    error = assert_raises(Synthient::APIError) { new_client(server).proxies.export_meta("latest", variant: "lite") }

    assert_equal 404, error.status
    assert_equal 1, server.requests.size
  end

  def test_export_volume
    server = serve { json(200, VOLUME) }
    client = new_client(server)
    volume = client.proxies.export_volume(days: 7)
    client.proxies.export_volume

    assert_equal ["/api/v4/feeds/proxies/export/daily?days=7", "/api/v4/feeds/proxies/export/daily"], server.paths
    assert_equal "proxies", volume.stream
    daily, hourly = volume.days

    assert_equal Date.new(2026, 11, 16), daily.date
    assert_equal Synthient::ExportKind::DAILY, daily.kind
    assert_equal 19_629_681_638, daily.size_bytes
    assert_equal 1_440_452_210, daily.row_count
    assert_equal Synthient::ExportKind::HOURLY, hourly.kind
    assert_equal 3, hourly.snapshots
  end

  def test_export_volume_validates_days
    server = serve { json(200, VOLUME) }
    client = new_client(server)

    [0, -1, 1.5, "7"].each { |days| assert_raises(ArgumentError) { client.proxies.export_volume(days:) } }
    assert_empty server.requests
  end

  def test_export_formats_and_entities
    whois = META.merge(
      "stream" => "whois", "format" => "tar.gz", "schema" => { "fields" => [] },
      "formats" => [{ "format" => "tar.gz", "size_bytes" => 997_234_948, "checksum" => "add0" }],
      "entities" => [
        { "entity" => "asns", "row_count" => 123_778, "size_bytes" => 5_442_736, "checksum" => "062f",
          "schema" => { "fields" => [{ "name" => "asn", "type" => "int64" }, { "name" => "updated", "type" => "timestamp" }] } },
        { "entity" => "contacts", "row_count" => 6_459_660, "size_bytes" => 205_447_373, "checksum" => "cf61",
          "schema" => { "fields" => [{ "name" => "emails", "type" => "list<string>" }] } },
        { "entity" => "registrars", "row_count" => 1, "size_bytes" => 1, "checksum" => "00" }
      ]
    )
    server = serve { json(200, whois) }
    meta = new_client(server).proxies.export_meta("latest")

    assert_equal Synthient::ExportFormat::TAR_GZ, meta.format
    assert_equal [Synthient::ExportFormat::TAR_GZ], meta.formats.map(&:format)
    assert_equal 997_234_948, meta.formats.first.size_bytes
    assert_empty meta.schema.fields
    assert_equal [Synthient::WhoisEntity::ASNS, Synthient::WhoisEntity::CONTACTS, "registrars"], meta.entities.map(&:entity)
    assert_equal %w[int64 timestamp], meta.entities.first.schema.fields.map(&:type)
    assert_equal "list<string>", meta.entities[1].schema.fields.first.type
    assert_nil meta.entities.last.schema
    assert_nil meta.variant
  end

  def test_schema_fields_null_or_missing
    [{ "fields" => nil }, {}].each do |schema|
      server = serve { json(200, META.merge("schema" => schema)) }
      fields = new_client(server).proxies.export_meta("latest").schema.fields

      assert_empty fields, schema.inspect
      assert_predicate fields, :frozen?
    end
  end

  def test_live_column_types
    types = %w[double int32 date float timestamp list<string>]
    fields = types.map { |type| { "name" => type, "type" => type } }
    server = serve { json(200, META.merge("schema" => { "fields" => fields })) }

    assert_equal types, new_client(server).proxies.export_meta("latest").schema.fields.map(&:type)
  end

  def test_exports_require_formats
    server = serve { page([EXPORT.except("formats")]) }
    error = assert_raises(Synthient::DecodeError) { new_client(server).proxies.list_exports }

    assert_equal "ExportPage.feeds[0].formats is required", error.message
  end

  def test_each_export_follows_cursors_through_empty_pages
    server = serve do |request|
      case request.path
      when /export\z/ then page([EXPORT], "c1")
      when /cursor=c1/ then page([], "c2")
      when /cursor=c2/ then page([EXPORT.merge("id" => "2026-05-07/20")])
      end
    end
    ids = new_client(server).proxies.each_export.map(&:id)

    assert_equal ["2026-05-07/21", "2026-05-07/20"], ids
    assert_equal 3, server.requests.size
  end

  def test_each_export_keeps_limit_and_start_cursor
    server = serve { |request| request.path.include?("cursor=c9") ? page([EXPORT], "c10") : page([]) }
    new_client(server).proxies.each_export(limit: 5, cursor: "c9").to_a

    assert_equal ["/api/v4/feeds/proxies/export?cursor=c9&limit=5", "/api/v4/feeds/proxies/export?cursor=c10&limit=5"],
                 server.paths
  end

  def test_each_export_detects_repeated_cursor
    server = serve { |request| request.path.include?("cursor=c2") ? page([EXPORT], "c1") : page([EXPORT], "c2") }
    error = assert_raises(Synthient::Error) { new_client(server).proxies.each_export.to_a }

    assert_equal "export listing returned a repeated cursor", error.message
    start = serve { page([EXPORT], "c1") }

    assert_raises(Synthient::Error) { new_client(start).proxies.each_export(cursor: "c1").to_a }
  end

  def test_each_export_is_lazy
    server = serve { page([EXPORT, EXPORT], "c1") }
    exports = new_client(server).proxies.each_export

    assert_empty server.requests
    exports.first

    assert_equal 1, server.requests.size
  end

  def test_each_export_raises_later_page_errors
    server = serve { |request| request.path.include?("cursor") ? problem(500, {}) : page([EXPORT], "c1") }
    seen = []
    error = assert_raises(Synthient::APIError) { new_client(server, max_retries: 0).proxies.each_export { |e| seen << e } }

    assert_equal 500, error.status
    assert_equal 1, seen.size
  end

  def test_each_export_block_exceptions_pass_through
    server = serve { page([EXPORT, EXPORT], "c1") }
    seen = []
    assert_raises(StopIteration) do
      new_client(server).proxies.each_export do |export|
        seen << export
        raise StopIteration if seen.size == 2
      end
    end

    assert_equal 2, seen.size
    assert_equal 1, server.requests.size
  end

  def test_empty_cursor_ends_iteration
    server = serve { page([EXPORT], "") }

    assert_equal 1, new_client(server).proxies.each_export.to_a.size
  end
end
