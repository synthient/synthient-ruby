# frozen_string_literal: true

require_relative "test_helper"

# Checks the models and client against the OpenAPI spec the SDK was last
# updated to, in .sdkgen/openapi.json.
class ConformanceTest < SynthientTest
  SPEC = JSON.parse(File.read(File.expand_path("../.sdkgen/openapi.json", __dir__), encoding: "UTF-8"))
  SCHEMAS = SPEC.dig("components", "schemas")

  MODELS = {
    "IpProvidersResponse" => Synthient::IPInfo,
    "NetworkInfo" => Synthient::Network,
    "LocationInfo" => Synthient::Location,
    "IntelligenceInfo" => Synthient::Intelligence,
    "ProviderEntry" => Synthient::Provider,
    "DeviceInfo" => Synthient::Device,
    "AccountInfoResponse" => Synthient::Account,
    "Organization" => Synthient::Organization,
    "LookupQuota" => Synthient::LookupQuota,
    "AccountAPIKey" => Synthient::AccountAPIKey,
    "ExportListResponse" => Synthient::ExportPage,
    "ExportListItem" => Synthient::Export,
    "ExportMetaResponse" => Synthient::ExportMeta,
    "ExportFormatFile" => Synthient::ExportFile,
    "ExportEntityFile" => Synthient::ExportEntity,
    "ExportDailyResponse" => Synthient::ExportVolume,
    "ExportDailyItem" => Synthient::ExportVolumeDay,
    "Schema" => Synthient::ParquetSchema,
    "ProjectedColumn" => Synthient::ParquetColumn,
    "ProxyStreamEntry" => Synthient::ProxyEvent,
    "AnonymizerStreamEntry" => Synthient::AnonymizerEvent,
    "TorrentStreamEntry" => Synthient::TorrentEvent,
    "TorrentFileEntry" => Synthient::TorrentFile,
    "TorrentPeerEntry" => Synthient::TorrentPeer,
    "JA4TStreamEntry" => Synthient::JA4TEvent,
    "HoneypotMeta" => Synthient::HeliosMeta,
    "HoneypotHTTPStreamEntry" => Synthient::HeliosHTTPEvent,
    "HoneypotHTTPSStreamEntry" => Synthient::HeliosHTTPSEvent,
    "TLSClientHello" => Synthient::TLSClientHello,
    "TLSCodeName" => Synthient::TLSCodeName,
    "TLSExtension" => Synthient::TLSExtension,
    "HoneypotDNSStreamEntry" => Synthient::HeliosDNSEvent,
    "HoneypotADBStreamEntry" => Synthient::HeliosADBEvent
  }.freeze

  UNMODELED = {
    "IpBatchRequest" => "built by Client#lookup_ips",
    "IpBatchResponse" => "Client#lookup_ips returns its results",
    "ProblemDetails" => "parsed into APIError",
    "ValidationProblemDetails" => "parsed into APIError"
  }.freeze

  VALUE_SETS = {
    "NetworkInfo.type" => Synthient::NetworkType,
    "DeviceInfo.os" => Synthient::OS,
    "AccountInfoResponse.scopes" => Synthient::Scope,
    "Organization.relation" => Synthient::Relation,
    "ExportListItem.kind" => Synthient::ExportKind,
    "ExportMetaResponse.kind" => Synthient::ExportKind,
    "ExportDailyItem.kind" => Synthient::ExportKind,
    "ExportMetaResponse.format" => Synthient::ExportFormat,
    "ExportFormatFile.format" => Synthient::ExportFormat,
    "ExportEntityFile.entity" => Synthient::WhoisEntity,
    "ProjectedColumn.type" => Synthient::ParquetType,
    "ProxyStreamEntry.type" => Synthient::ProxyType,
    "AnonymizerStreamEntry.type" => Synthient::ProxyType,
    "JA4TStreamEntry.type" => Synthient::ProxyType,
    "HoneypotHTTPSStreamEntry.transport" => Synthient::HeliosTransport,
    "HoneypotDNSStreamEntry.transport" => Synthient::HeliosTransport
  }.freeze

  # Deprecated constants kept until the next major version, though the spec
  # no longer lists their values.
  DEPRECATED_VALUES = { "AccountInfoResponse.scopes" => %w[ADMIN_PROXIES] }.freeze

  # Deprecated operations the client keeps until the next major version,
  # though the spec no longer lists them.
  DEPRECATED_OPERATIONS = { "GET /lookup/domain/{domain}" => "Client#lookup_domain" }.freeze

  UNIX_TIME_FIELDS = %w[timestamp last_seen created_at date].freeze

  def test_every_schema_is_accounted_for
    assert_equal SCHEMAS.keys.sort, (MODELS.keys + UNMODELED.keys).sort
  end

  def test_models_match_schemas
    @enums = {}
    MODELS.each { |name, model| check_model(name, SCHEMAS.fetch(name), model) }

    assert_empty @enums.keys - VALUE_SETS.keys, "spec enums without a value set"
    assert_empty VALUE_SETS.keys - @enums.keys, "value sets without a spec enum"
    VALUE_SETS.each do |where, set|
      values = set.constants.map { |name| set.const_get(name) } - DEPRECATED_VALUES.fetch(where, [])

      assert_equal @enums[where], values.sort, "#{where} enum values"
    end
  end

  def test_members_do_not_shadow_data_methods
    MODELS.each_value do |model|
      assert_empty model.members & Data.instance_methods, model.name
    end
  end

  def test_client_covers_every_operation
    in_spec = SPEC["paths"].flat_map do |path, operations|
      (operations.keys & %w[get post put patch delete]).map { |verb| "#{verb.upcase} #{path}" }
    end
    expected = in_spec + DEPRECATED_OPERATIONS.keys
    templates = expected.map { |operation| operation.split.last }.uniq.map do |path|
      [path, Regexp.new("\\A/api/v4#{path.gsub(/\{[^}]+\}/, "[^/]+")}\\z")]
    end
    server = serve { json(500, {}) }
    client = new_client(server, max_retries: 0)
    calls = [
      -> { client.lookup_ip("8.8.8.8") }, -> { client.lookup_ips(["8.8.8.8"]) }, -> { client.lookup_domain("example.com") },
      -> { client.account }, -> { client.health }
    ]
    %i[proxies anonymizers torrents ja4t helios_http helios_https helios_dns helios_adb].each do |name|
      feed = client.public_send(name)
      calls.push(-> { feed.stream.to_a }, -> { feed.list_exports }, -> { feed.export_meta("2026-05-07") },
                 -> { feed.export_meta("2026-05-07/7") }, -> { feed.download_url("2026-05-07") },
                 -> { feed.download_url("2026-05-07/7") }, -> { feed.export_volume })
    end
    %i[geolocation whois].each do |name|
      dataset = client.public_send(name)
      calls.push(-> { dataset.list_exports }, -> { dataset.export_meta("2026-05-07") },
                 -> { dataset.download_url("2026-05-07") }, -> { dataset.export_volume })
    end
    calls.each do |call|
      call.call
    rescue Synthient::APIError
      nil
    end
    covered = server.requests.map do |request|
      path = request.path.split("?").first
      matches = templates.select { |_, pattern| pattern.match?(path) }.map(&:first)
      "#{request.verb} #{matches.min_by { |template| template.count("{") }}"
    end

    assert_equal expected.sort, covered.uniq.sort
    assert_equal 68, in_spec.size
  end

  private

  def check_model(path, schema, model)
    properties = schema.fetch("properties", {})
    required = schema.fetch("required", [])
    fields = model.fields.to_h { |field| [field.wire, field] }

    assert_equal properties.keys.sort, fields.keys.sort, "#{path} fields"
    properties.each do |wire, property|
      field = fields.fetch(wire)
      where = "#{path}.#{wire}"

      # A required but nullable field is optional, because nil stands for both.
      assert_equal required.include?(wire) && !property["nullable"], field.required, "#{where} required"
      check_type(where, property, field.type)
      values = %w[enum x-extensible-enum].sum([]) { |key| property[key] || property.dig("items", key) || [] }
      @enums[where] = values.sort if values.size >= 2
    end
  end

  def check_type(where, property, type)
    ref = property["$ref"] || (property["allOf"]&.size == 1 && property["allOf"].first["$ref"])
    return assert_equal(MODELS.fetch(ref.split("/").last), type, where) if ref

    case property["type"]
    when "integer"
      if UNIX_TIME_FIELDS.include?(where.split(".").last)
        assert_equal [:unix_time, "int64"], [type, property["format"]], where
      else
        assert_equal :integer, type, where
      end
    when "number" then assert_equal :float, type, where
    when "boolean" then assert_equal :bool, type, where
    when "string"
      expected = { "byte" => [:bytes], "date-time" => [:time] }.fetch(property["format"], %i[string date ip])

      assert_includes expected, type, where
    when "array"
      assert_kind_of Array, type, where
      check_type("#{where}[]", property["items"], type.first)
    when "object"
      if property["additionalProperties"]
        assert_kind_of Hash, type, where
        check_type("#{where}{}", property["additionalProperties"], type.values.first)
      else
        assert_respond_to type, :fields, "#{where} is an inline object, so it needs a model"
        check_model(where, property, type)
      end
    else
      flunk "#{where} has unsupported type #{property["type"].inspect}"
    end
  end
end
