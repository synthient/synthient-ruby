# frozen_string_literal: true

require_relative "test_helper"

class DatasetTest < SynthientTest
  META = {
    "id" => "2026-11-17", "stream" => "geolocation", "kind" => "daily", "format" => "parquet", "date" => 1_794_873_600,
    "rows" => 27_456_467, "size" => 466_431_938, "checksum" => "9712", "created_at" => 1_794_960_045,
    "schema" => { "fields" => [{ "name" => "latitude", "type" => "double" }] },
    "formats" => [
      { "format" => "parquet", "size_bytes" => 466_431_938, "checksum" => "9712" },
      { "format" => "csv", "size_bytes" => 540_196_440, "checksum" => "de74" },
      { "format" => "mmdb", "size_bytes" => 1_874_587_084, "checksum" => "ae71" }
    ]
  }.freeze

  EXPORT = SynthientTest::EXPORT.except("hour").merge(
    "id" => "2026-11-17", "kind" => "daily", "date" => "2026-11-17",
    "download_path" => "/api/v4/feeds/geolocation/export/2026-11-17", "formats" => META["formats"]
  ).freeze

  def page(exports, next_cursor = nil)
    json(200, { "stream" => "geolocation", "feeds" => exports, "next_cursor" => next_cursor }.compact)
  end

  def test_routes
    server = serve do |request|
      case request.path
      when %r{/export(\?|\z)} then page([EXPORT])
      when %r{/export/daily} then json(200, { "stream" => "whois", "days" => [] })
      when %r{/meta} then json(200, META)
      else [307, { "location" => "/file.mmdb" }, ""]
      end
    end
    client = new_client(server)
    %i[geolocation whois].each do |name|
      dataset = client.public_send(name)
      dataset.list_exports(limit: 10, day: Date.new(2026, 11, 17))
      dataset.export_volume(days: 30)
      dataset.export_meta("latest")
      dataset.download_url(Date.new(2026, 11, 17))
    end

    assert_equal %w[
      /api/v4/feeds/geolocation/export?day=2026-11-17&limit=10
      /api/v4/feeds/geolocation/export/daily?days=30
      /api/v4/feeds/geolocation/export/latest/meta
      /api/v4/feeds/geolocation/export/2026-11-17
      /api/v4/feeds/whois/export?day=2026-11-17&limit=10
      /api/v4/feeds/whois/export/daily?days=30
      /api/v4/feeds/whois/export/latest/meta
      /api/v4/feeds/whois/export/2026-11-17
    ], server.paths
  end

  def test_format_is_sent_only_when_set
    server = serve do |request|
      if request.path.include?("/meta")
        json(200, META.merge("format" => request.path[/format=([^&]+)/, 1] || "parquet"))
      else
        [307, { "location" => "/file" }, ""]
      end
    end
    client = new_client(server)
    formats = [nil, "", Synthient::ExportFormat::CSV, Synthient::ExportFormat::MMDB, Synthient::ExportFormat::TAR_GZ]
    metas = formats.map { |format| client.geolocation.export_meta("2026-11-17", format:) }
    client.whois.download_url("latest", format: Synthient::ExportFormat::TAR_GZ)
    client.geolocation.download_url("latest")

    assert_equal %w[parquet parquet csv mmdb tar.gz], metas.map(&:format)
    assert_equal [Synthient::ExportFormat::PARQUET, Synthient::ExportFormat::CSV, Synthient::ExportFormat::MMDB],
                 metas.first.formats.map(&:format)
    assert_equal %w[
      /api/v4/feeds/geolocation/export/2026-11-17/meta
      /api/v4/feeds/geolocation/export/2026-11-17/meta
      /api/v4/feeds/geolocation/export/2026-11-17/meta?format=csv
      /api/v4/feeds/geolocation/export/2026-11-17/meta?format=mmdb
      /api/v4/feeds/geolocation/export/2026-11-17/meta?format=tar.gz
      /api/v4/feeds/whois/export/latest?format=tar.gz
      /api/v4/feeds/geolocation/export/latest
    ], server.paths
    assert_raises(TypeError) { client.geolocation.export_meta("latest", format: :csv) }
  end

  def test_hourly_ids_send_no_request
    server = serve { json(200, META) }
    client = new_client(server)

    ["2026-11-17/7", "2026-11-17/07", "2026-11-17/24", "2026-02-30", "latest/3", ""].each do |export|
      assert_raises(ArgumentError, export) { client.geolocation.export_meta(export) }
      assert_raises(ArgumentError, export) { client.whois.download_url(export) }
    end
    [Time.utc(2026, 11, 17, 7), DateTime.new(2026, 11, 17), nil, 20_261_117].each do |export|
      assert_raises(TypeError, export.inspect) { client.geolocation.export_meta(export) }
      assert_raises(TypeError, export.inspect) { client.whois.download_url(export) }
    end
    error = assert_raises(ArgumentError) { client.whois.export_meta("2026-11-17/7") }

    assert_equal 'invalid export ID "2026-11-17/7": datasets have no hourly exports', error.message
    assert_empty server.requests
  end

  def test_each_export_keeps_day
    server = serve { |request| request.path.include?("cursor") ? page([EXPORT]) : page([EXPORT], "c1") }
    exports = new_client(server).whois.each_export(day: "2026-11-17").to_a

    assert_equal 2, exports.size
    assert_equal ["/api/v4/feeds/whois/export?day=2026-11-17", "/api/v4/feeds/whois/export?cursor=c1&day=2026-11-17"],
                 server.paths
  end

  def test_whois_list_item_entities
    entity = { "entity" => "networks", "row_count" => 10, "size_bytes" => 20, "checksum" => "ff" }
    server = serve { page([EXPORT.merge("entities" => [entity], "formats" => [META["formats"].first])]) }
    export = new_client(server).whois.list_exports.exports.first

    assert_equal Synthient::WhoisEntity::NETWORKS, export.entities.first.entity
    assert_nil export.entities.first.schema
  end

  def test_download_matches_feed_redirect_rules
    file = "mmdb bytes".b
    store = serve { [200, { "content-type" => "application/octet-stream" }, file] }
    signed = "/geolocation/2026-11-17.mmdb?X-Amz-Signature=secret-signature"
    server = serve { [307, { "location" => "http://localhost:#{store.port}#{signed}" }, ""] }
    data = "".b
    new_client(server).geolocation.download("latest", format: Synthient::ExportFormat::MMDB) { |chunk| data << chunk }

    assert_equal file, data
    assert_equal ["/api/v4/feeds/geolocation/export/latest?format=mmdb"], server.paths
    assert_equal "test-key", server.requests.first.headers["x-api-key"]
    assert_equal signed, store.requests.first.path
    assert_nil store.requests.first.headers["x-api-key"]
    assert_equal "identity", store.requests.first.headers["accept-encoding"]
  end

  def test_download_enumerator_and_errors
    server = serve { problem(404, { "detail" => "This snapshot has no csv file; available: tar.gz" }) }
    chunks = new_client(server).whois.download("latest", format: Synthient::ExportFormat::CSV)

    assert_kind_of Enumerator, chunks
    assert_empty server.requests
    error = assert_raises(Synthient::APIError) { chunks.to_a }

    assert_equal 404, error.status
    assert_equal "This snapshot has no csv file; available: tar.gz", error.detail
  end
end
