# frozen_string_literal: true

require_relative "test_helper"

class AccountTest < SynthientTest
  def test_account
    server = serve { json(200, ACCOUNT) }
    account = new_client(server).account

    assert_equal ["/api/v4/account/me"], server.paths
    assert_equal "dev@example.com", account.email
    assert_equal Synthient::Relation::OWNER, account.organization.relation
    assert_equal %w[BASIC PROXY_FEEDS FUTURE_SCOPE], account.scopes
    assert_equal 9_000_000_000, account.lookup_quota.credits
    assert_equal Time.utc(2026, 9, 28, 19, 4, 52, 463_869), account.api_key.created_at
  end

  def test_account_without_api_key
    server = serve { json(200, ACCOUNT.except("api_key")) }

    assert_nil new_client(server).account.api_key
  end

  def test_account_rejects_invalid_created_at
    server = serve { json(200, ACCOUNT.merge("api_key" => ACCOUNT["api_key"].merge("created_at" => "yesterday"))) }

    error = assert_raises(Synthient::DecodeError) { new_client(server).account }
    assert_equal "Account.api_key.created_at is not a valid time", error.message
  end

  def test_health
    server = serve { json(200, { "status" => "ok" }) }

    assert_nil new_client(server).health
    assert_equal ["/api/v4/health"], server.paths
  end

  def test_unhealthy_responses_are_not_retried
    [
      json(503, { "status" => "unavailable" }),
      [503, { "content-type" => "text/html" }, "<html>down</html>"],
      [401, { "content-type" => "text/plain" }, "401 invalid api key"]
    ].each do |response|
      server = serve { response }
      error = assert_raises(Synthient::APIError) { new_client(server).health }

      assert_equal response[0], error.status
      assert_equal 1, server.requests.size
    end
  end

  def test_health_requires_json_object
    server = serve { json(200, "[]") }

    assert_raises(Synthient::DecodeError) { new_client(server).health }
  end
end
