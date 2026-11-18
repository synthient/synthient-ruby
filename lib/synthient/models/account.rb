# frozen_string_literal: true

module Synthient
  # A member's role in an organization.
  module Relation
    OWNER = "OWNER"
    ADMIN = "ADMIN"
    MEMBER = "MEMBER"
  end

  # API key scopes. New values may be added.
  module Scope
    BASIC = "BASIC"
    PROXY_FEEDS = "PROXY_FEEDS"
    PROXY_FIREHOSE = "PROXY_FIREHOSE"
    ANONYMIZERS_FEED = "ANONYMIZERS_FEED"
    ANONYMIZERS_STREAM = "ANONYMIZERS_STREAM"
    JA3_FEED = "JA3_FEED"
    JA3_STREAM = "JA3_STREAM"
    TORRENTS_FEED = "TORRENTS_FEED"
    TORRENTS_STREAM = "TORRENTS_STREAM"
    HONEYPOT_HTTP_FEED = "HONEYPOT_HTTP_FEED"
    HONEYPOT_HTTP_STREAM = "HONEYPOT_HTTP_STREAM"
    HONEYPOT_HTTPS_FEED = "HONEYPOT_HTTPS_FEED"
    HONEYPOT_HTTPS_STREAM = "HONEYPOT_HTTPS_STREAM"
    HONEYPOT_ADB_FEED = "HONEYPOT_ADB_FEED"
    HONEYPOT_ADB_STREAM = "HONEYPOT_ADB_STREAM"
    HONEYPOT_DNS_FEED = "HONEYPOT_DNS_FEED"
    HONEYPOT_DNS_STREAM = "HONEYPOT_DNS_STREAM"
    JA4_FEED = "JA4_FEED"
    JA4_STREAM = "JA4_STREAM"
    JA4T_FEED = "JA4T_FEED"
    JA4T_STREAM = "JA4T_STREAM"
    GEOLOCATION_FEED = "GEOLOCATION_FEED"
    WHOIS_FEED = "WHOIS_FEED"
    # Reserved: no operation accepts it yet.
    WHOIS_STREAM = "WHOIS_STREAM"
    # Reserved for an upcoming network IOC feed.
    NETWORK_IOCS_FEED = "NETWORK_IOCS_FEED"
    # Reserved for an upcoming network IOC feed.
    NETWORK_IOCS_STREAM = "NETWORK_IOCS_STREAM"
    # Reserved for an upcoming file IOC feed.
    FILE_IOCS_FEED = "FILE_IOCS_FEED"
    # Reserved for an upcoming file IOC feed.
    FILE_IOCS_STREAM = "FILE_IOCS_STREAM"
    # A dashboard permission that authorizes no API operation.
    HELIOS = "HELIOS"
    # @deprecated The API no longer lists this scope, and it never authorized
    #   an API operation. It will be removed in the next major version.
    ADMIN_PROXIES = "ADMIN_PROXIES"
  end

  # +relation+ is the account's role, one of Relation.
  Organization = Model.define do
    required :id, :string
    required :name, :string
    required :relation, :string
  end

  # +resets_in+ is the number of seconds until the credits reset.
  LookupQuota = Model.define do
    required :credits, :integer
    required :resets_in, :integer
  end

  # The API key that made the request.
  AccountAPIKey = Model.define do
    required :id, :string
    required :name, :string
    required :created_at, :time
  end

  # The account that owns the API key. +scopes+ holds Scope values.
  # +api_key+ is nil if the key was deleted while the request was in flight.
  Account = Model.define do
    required :email, :string
    required :first_name, :string
    required :last_name, :string
    required :organization, Organization
    required :scopes, [:string]
    required :lookup_quota, LookupQuota
    optional :api_key, AccountAPIKey
  end
end
