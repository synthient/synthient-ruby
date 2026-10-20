# frozen_string_literal: true

module Synthient
  # The kinds of service seen on an address. New values may be added.
  module ProxyType
    FREE_VPN = "FREE_VPN"
    COMMERCIAL_VPN = "COMMERCIAL_VPN"
    ENTERPRISE_VPN = "ENTERPRISE_VPN"
    MOBILE_PROXY = "MOBILE_PROXY"
    BLOCKCHAIN_PROXY = "BLOCKCHAIN_PROXY"
    RESIDENTIAL_PROXY = "RESIDENTIAL_PROXY"
    PUBLIC_PROXY = "PUBLIC_PROXY"
    DATACENTER_PROXY = "DATACENTER_PROXY"
    TOR_NODE = "TOR_NODE"
    PRIVATE_RELAY = "PRIVATE_RELAY"
    BOTNET = "BOTNET"
    SEARCH_ENGINE = "SEARCH_ENGINE"
    AI_CRAWLER = "AI_CRAWLER"
    SOCIAL_MEDIA = "SOCIAL_MEDIA"
    UPTIME_MONITOR = "UPTIME_MONITOR"
    LINK_PREVIEW = "LINK_PREVIEW"
    SEO_CRAWLER = "SEO_CRAWLER"
    WEB_ARCHIVER = "WEB_ARCHIVER"
    WEBHOOK_PROVIDER = "WEBHOOK_PROVIDER"
    PAYMENT_PROCESSOR = "PAYMENT_PROCESSOR"
    INTERNET_SCANNER = "INTERNET_SCANNER"
  end

  # +type+ is one of ProxyType.
  ProxyEvent = Model.define do
    optional :ip, :string
    optional :provider, :string
    optional :type, :string
    optional :country_code, :string
    optional :asn, :integer
    optional :timestamp, :unix_time
  end

  # +type+ is one of ProxyType, and +country_code+ and +asn+ describe
  # +range_start+.
  AnonymizerEvent = Model.define do
    optional :range_start, :string
    optional :range_end, :string
    optional :provider, :string
    optional :type, :string
    optional :country_code, :string
    optional :asn, :integer
    optional :timestamp, :unix_time
  end

  # +length+ is in bytes.
  TorrentFile = Model.define do
    optional :path, :string
    optional :length, :integer
  end

  # +source+ is where the peer was found, such as "DHT", "PEX", or "tracker".
  TorrentPeer = Model.define do
    optional :ip, :string
    optional :port, :integer
    optional :source, :string
    optional :encrypted, :bool
  end

  # +info_hash+ is the hex SHA-1 info hash, and sizes are in bytes.
  TorrentEvent = Model.define do
    optional :info_hash, :string
    optional :name, :string
    optional :magnet_uri, :string
    optional :total_size, :integer
    optional :piece_length, :integer
    optional :file_count, :integer
    optional :files, [TorrentFile]
    optional :peers, [TorrentPeer]
    optional :timestamp, :unix_time
  end

  # A JA4T TCP fingerprint sighting. +type+ is one of ProxyType.
  JA4TEvent = Model.define do
    optional :ip, :string
    optional :ja4t, :string
    optional :provider, :string
    optional :type, :string
    optional :country_code, :string
    optional :asn, :integer
    optional :timestamp, :unix_time
  end

  # The Helios honeypot sensor that captured an event. +proxy_ip+ and
  # +provider+ are the proxy exit address and service the traffic arrived
  # through.
  HeliosMeta = Model.define do
    optional :proxy_ip, :string
    optional :server, :string
    optional :pool_id, :string
    optional :provider, :string
  end

  # +http_method+ is the request method. The API calls it +method+, which
  # would shadow Object#method.
  HTTPRequestDetails = Model.define do
    optional :http_method, :string, wire: "method"
    optional :uri, :string
    optional :version, :string
    optional :headers, { string: :string }
  end

  # +domain+ is the host the proxy tunnel was opened to, and +raw+ holds the
  # raw request bytes.
  HeliosHTTPEvent = Model.define do
    required :timestamp, :unix_time
    required :tunnel_id, :integer
    required :domain, :string
    required :port, :integer
    required :protocol, :string
    required :meta, HeliosMeta
    optional :details, HTTPRequestDetails
    optional :raw, :bytes
  end

  # A TLS registry code point and its name. GREASE values are named
  # "GREASE(0x....)".
  TLSCodeName = Model.define do
    optional :code, :integer
    optional :name, :string
  end

  # +length+ is the extension body length in bytes.
  TLSExtension = Model.define do
    optional :code, :integer
    optional :name, :string
    optional :length, :integer
  end

  # Fields the sensor could not parse are nil.
  TLSClientHello = Model.define do
    optional :record_version, :string
    optional :handshake_version, :string
    optional :client_random, :string
    optional :session_id, :string
    optional :session_id_length, :integer
    optional :cipher_suites, [TLSCodeName]
    optional :compression_methods, [:integer]
    optional :extensions, [TLSExtension]
    optional :sni, :string
    optional :alpn, [:string]
    optional :supported_versions, [:string]
    optional :supported_groups, [TLSCodeName]
    optional :signature_algorithms, [TLSCodeName]
    optional :ec_point_formats, [:string]
    optional :key_share_groups, [:string]
    optional :psk_key_exchange_modes, [:string]
    optional :compress_certificate, [:string]
    optional :has_grease, :bool
    optional :application_settings, :bool
    optional :delegated_credentials, :bool
    optional :encrypt_then_mac, :bool
    optional :extended_master_secret, :bool
    optional :post_handshake_auth, :bool
    optional :renegotiation_info, :bool
    optional :signed_certificate_timestamps, :bool
    optional :status_request, :bool
  end

  # A TLS ClientHello captured by a Helios honeypot. +details+ is nil when the
  # sensor could not parse the handshake. +raw+ is always nil, because the
  # sensors do not capture handshake bytes.
  HeliosHTTPSEvent = Model.define do
    required :timestamp, :unix_time
    required :tunnel_id, :integer
    required :domain, :string
    required :port, :integer
    required :protocol, :string
    required :meta, HeliosMeta
    optional :details, TLSClientHello
    optional :raw, :string
  end

  # A destination a Helios honeypot tunnel was asked to reach. Despite the
  # feed's name, it is not a DNS query: names resolved inside a tunneled DNS
  # session are not visible.
  HeliosDNSEvent = Model.define do
    required :timestamp, :unix_time
    required :tunnel_id, :integer
    required :domain, :string
    required :port, :integer
    required :protocol, :string
    required :meta, HeliosMeta
  end

  # An Android Debug Bridge shell command captured by a Helios honeypot. It
  # has no timestamp because the sensor sends none. +sequential_id+ is the
  # 1-based position of the command in its session. +payload_hash+ is the hex
  # SHA-256 the sensor assigns to the session's payload, sent as +hash+: it is
  # not a hash of +command+, and every command in a session shares it.
  HeliosADBEvent = Model.define do
    required :session, :string
    required :sequential_id, :integer
    required :command, :string
    required :payload_hash, :string, wire: "hash"
  end
end
