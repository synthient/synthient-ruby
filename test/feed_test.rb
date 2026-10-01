# frozen_string_literal: true

require_relative "test_helper"

class FeedTest < SynthientTest
  META = {
    "id" => "2026-05-07", "stream" => "proxies", "kind" => "daily", "format" => "parquet", "date" => 1_778_112_000,
    "rows" => 1200, "size" => 1_048_576, "checksum" => "ab12", "created_at" => 1_778_187_600,
    "schema" => { "fields" => [{ "name" => "ip", "type" => "string" }, { "name" => "asn", "type" => "uint32" }] }
  }.freeze

  FEEDS = {
    proxies: "proxies", anonymizers: "anonymizers", torrents: "torrents", ja4t: "ja4t",
    helios_http: "helio/http", helios_https: "helio/https", helios_dns: "helio/dns", helios_adb: "helio/adb"
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

  def test_meta_routes_for_every_feed
    server = serve { json(200, META) }
    client = new_client(server)
    FEEDS.each do |feed, path|
      client.public_send(feed).export_meta("2026-05-03/7")

      assert_equal "/api/v4/feeds/#{path}/export/2026-05-03/7/meta", server.paths.last
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
  end

  def test_list_exports_validates_arguments
    server = serve { page([]) }
    client = new_client(server)

    [0, -1, 2.0, "2"].each { |limit| assert_raises(ArgumentError) { client.proxies.list_exports(limit:) } }
    assert_raises(TypeError) { client.proxies.list_exports(cursor: 5) }
    client.proxies.list_exports(cursor: "")

    assert_equal ["/api/v4/feeds/proxies/export"], server.paths
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

  def test_empty_cursor_ends_iteration
    server = serve { page([EXPORT], "") }

    assert_equal 1, new_client(server).proxies.each_export.to_a.size
  end
end
