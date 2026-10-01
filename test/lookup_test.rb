# frozen_string_literal: true

require_relative "test_helper"

class LookupTest < SynthientTest
  def test_lookup_ip_decodes_response
    server = serve { json(200, IP_INFO) }
    info = new_client(server).lookup_ip("8.8.8.8")

    assert_equal IPAddr.new("8.8.8.8"), info.ip
    assert_equal 15_169, info.network.asn
    assert_equal Synthient::NetworkType::DATACENTER, info.network.type
    assert_nil info.network.abuse_phone
    assert_in_delta 37.4056, info.location.latitude
    assert_equal 12, info.intelligence.risk_score
    assert_equal ["DATACENTER"], info.intelligence.categories
    provider = info.intelligence.providers.first

    assert_equal "BRIGHTDATA", provider.name
    assert_equal Time.at(1_778_187_600, in: "UTC"), provider.last_seen
    assert_equal Synthient::OS::ANDROID, info.intelligence.devices.first.os
  end

  def test_lookup_ip_request_paths
    server = serve { json(200, IP_INFO) }
    client = new_client(server)
    client.lookup_ip("8.8.8.8")
    client.lookup_ip("2001:DB8:0::1")
    client.lookup_ip(IPAddr.new("::ffff:1.2.3.4"))
    client.lookup_ip(IPAddr.new("1.1.1.1"))

    assert_equal %w[/api/v4/lookup/ip/8.8.8.8 /api/v4/lookup/ip/2001:db8::1 /api/v4/lookup/ip/::ffff:1.2.3.4
                    /api/v4/lookup/ip/1.1.1.1], server.paths
  end

  def test_lookup_ip_rejects_invalid_addresses_without_a_request
    server = serve { json(200, IP_INFO) }
    client = new_client(server)

    ["", "8.8.8", "1.2.3.4/24", "fe80::1%eth0", "010.1.1.1", "example.com", "8.8.8.8 "].each do |ip|
      assert_raises(ArgumentError, ip) { client.lookup_ip(ip) }
    end
    assert_raises(ArgumentError) { client.lookup_ip(IPAddr.new("10.0.0.0/8")) }
    assert_raises(TypeError) { client.lookup_ip(134_744_072) }
    assert_raises(TypeError) { client.lookup_ip(nil) }
    assert_empty server.requests
  end

  def test_lookup_ip_sections_absent_or_null
    server = serve do |request|
      case request.path
      when %r{/1\.1\.1\.1\z} then json(200, { "ip" => "1.1.1.1" })
      when %r{/1\.0\.0\.1\z} then json(200, { "ip" => "1.0.0.1", "network" => nil, "location" => nil, "intelligence" => nil })
      end
    end
    client = new_client(server)

    [client.lookup_ip("1.1.1.1"), client.lookup_ip("1.0.0.1")].each do |info|
      assert_nil info.network
      assert_nil info.location
      assert_nil info.intelligence
    end
  end

  def test_lookup_ip_rejects_invalid_response
    server = serve { json(200, IP_INFO.merge("network" => IP_INFO["network"].merge("asn" => "15169"))) }

    error = assert_raises(Synthient::DecodeError) { new_client(server).lookup_ip("8.8.8.8") }
    assert_equal "IPInfo.network.asn is not a valid integer", error.message
  end

  def test_lookup_ips_sends_batch
    server = serve { json(200, { "results" => [IP_INFO, IP_INFO.merge("ip" => "1.1.1.1")] }) }
    results = new_client(server).lookup_ips(["8.8.8.8", IPAddr.new("1.1.1.1"), "2001:DB8::1"])
    request = server.requests.first

    assert_equal "POST", request.verb
    assert_equal "/api/v4/lookup/ips", request.path
    assert_equal "application/json", request.headers["content-type"]
    assert_equal({ "ips" => ["8.8.8.8", "1.1.1.1", "2001:db8::1"] }, JSON.parse(request.body))
    assert_equal [IPAddr.new("8.8.8.8"), IPAddr.new("1.1.1.1")], results.map(&:ip)
    assert_predicate results, :frozen?
  end

  def test_lookup_ips_accepts_enumerables
    server = serve { json(200, { "results" => [] }) }

    assert_empty new_client(server).lookup_ips(Set["8.8.8.8"])
    assert_equal({ "ips" => ["8.8.8.8"] }, JSON.parse(server.requests.first.body))
  end

  def test_lookup_ips_edge_cases_send_no_request
    server = serve { json(200, { "results" => [] }) }
    client = new_client(server)

    assert_empty client.lookup_ips([])
    error = assert_raises(ArgumentError) { client.lookup_ips(["8.8.8.8", "bad", "1.1.1.1"]) }
    assert_equal "invalid IP address at index 1", error.message
    error = assert_raises(ArgumentError) { client.lookup_ips(Array.new(1001, "8.8.8.8")) }
    assert_equal "1001 addresses exceed the batch limit of 1000", error.message
    assert_raises(TypeError) { client.lookup_ips("8.8.8.8") }
    assert_raises(TypeError) { client.lookup_ips(["8.8.8.8", 1]) }
    assert_empty server.requests
  end

  def test_lookup_ips_requires_results
    server = serve { json(200, {}) }

    assert_raises(Synthient::DecodeError) { new_client(server).lookup_ips(["8.8.8.8"]) }
  end

  def test_lookup_domain
    domain = {
      "domain" => "example.com", "status" => "active",
      "stats" => { "events_24h" => 5, "total_events_30d" => 80 },
      "unique_ips" => { "value_24h" => 2, "value_30d" => 9, "sparkline_24h" => [0, 1, 2] },
      "time_series" => [{ "date" => 1_778_112_000, "events" => 4, "unique_ips" => 2 }],
      "top_subdomains" => [{ "subdomain" => "www", "count" => 3 }],
      "top_ports" => [{ "port" => 443, "count" => 3 }],
      "geo_distribution" => [{ "country_code" => "DE", "events" => 3, "unique_ips" => 1 }],
      "hour_dow_heatmap" => Array.new(7) { Array.new(24, 0) },
      "activity_stats" => {
        "cadence" => "Activity is burst-driven with significant peaks.", "median_per_hour" => 0,
        "p95_per_hour" => 2, "peak_hour" => 13, "quiet_hour" => 4
      },
      "recent_events" => [{
        "timestamp" => 1_778_187_600, "source_ip_masked" => "203.0.113.7", "target_subdomain" => "www",
        "country_code" => "DE", "port" => 443
      }]
    }
    server = serve { json(200, domain) }
    info = new_client(server).lookup_domain("example.com", limit: 5)

    assert_equal ["/api/v4/lookup/domain/example.com?limit=5"], server.paths
    assert_equal Synthient::DomainStatus::ACTIVE, info.status
    assert_nil info.top_asn
    assert_equal Synthient::Cadence::BURST_DRIVEN, info.activity_stats.cadence
    assert_equal "203.0.113.7", info.recent_events.first.source_ip
    assert_equal 7, info.hour_dow_heatmap.size
  end

  def test_lookup_domain_escapes_path
    server = serve { json(200, {}) }
    client = new_client(server)

    ["a/b?c", "sp ace", "x;y,z", "bücher.de", "$&+:=@"].each do |domain|
      assert_raises(Synthient::DecodeError) { client.lookup_domain(domain) }
    end

    assert_equal %w[/api/v4/lookup/domain/a%2Fb%3Fc /api/v4/lookup/domain/sp%20ace /api/v4/lookup/domain/x%3By%2Cz
                    /api/v4/lookup/domain/b%C3%BCcher.de /api/v4/lookup/domain/$&+:=@], server.paths
  end

  def test_lookup_domain_rejects_invalid_input
    server = serve { json(200, {}) }
    client = new_client(server)

    ["", ".", ".."].each { |domain| assert_raises(ArgumentError) { client.lookup_domain(domain) } }
    [0, -1, 1.5, "5", true].each { |limit| assert_raises(ArgumentError) { client.lookup_domain("example.com", limit:) } }
    assert_raises(TypeError) { client.lookup_domain(:example) }
    assert_empty server.requests
  end
end
