# frozen_string_literal: true

module Synthient
  # A member's role in an organization.
  module Relation
    OWNER = "OWNER"
    ADMIN = "ADMIN"
    MEMBER = "MEMBER"
    ALL = constants.sort.map { |name| const_get(name) }.freeze
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
    ADMIN_PROXIES = "ADMIN_PROXIES"
    ALL = constants.sort.map { |name| const_get(name) }.freeze
  end

  # The organization an account belongs to. +relation+ is one of Relation.
  Organization = Model.define do
    required :id, :string
    required :name, :string
    required :relation, :string, enum: Relation
  end

  # The account's lookup credits. +resets_in+ is the number of seconds until
  # the credits reset.
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
  Account = Model.define do
    required :email, :string
    required :first_name, :string
    required :last_name, :string
    required :organization, Organization
    required :scopes, [:string], enum: Scope
    required :lookup_quota, LookupQuota
    optional :api_key, AccountAPIKey
  end
end
