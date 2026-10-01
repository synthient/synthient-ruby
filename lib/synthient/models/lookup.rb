# frozen_string_literal: true

module Synthient
  # Network types. New values may be added.
  module NetworkType
    MOBILE = "MOBILE"
    SATELLITE = "SATELLITE"
    IN_FLIGHT_WIFI = "IN_FLIGHT_WIFI"
    RESIDENTIAL = "RESIDENTIAL"
    CORPORATE = "CORPORATE"
    ACADEMIC = "ACADEMIC"
    DATACENTER = "DATACENTER"
    GOVERNMENT = "GOVERNMENT"
    ALL = constants.sort.map { |name| const_get(name) }.freeze
  end

  # Device operating systems. New values may be added.
  module OS
    ANDROID = "Android"
    CHROME_OS = "Chrome OS"
    FREEBSD = "FreeBSD"
    IOS = "iOS"
    LINUX = "Linux"
    MAC_OS_X = "Mac OS X"
    WINDOWS = "Windows"
    ALL = constants.sort.map { |name| const_get(name) }.freeze
  end

  # The network that announces an address. +asn+ is 0 if the address is not
  # routed. +type+ is one of NetworkType. +org+, +domain+, +abuse_email+, and
  # +abuse_phone+ are nil when unknown.
  Network = Model.define do
    required :asn, :integer
    required :isp, :string
    optional :org, :string
    optional :domain, :string
    required :type, :string, enum: NetworkType
    optional :abuse_email, :string
    optional :abuse_phone, :string
  end

  # The geolocation of an address. +country+ is an ISO 3166-1 alpha-2 code and
  # +timezone+ an IANA time zone name.
  Location = Model.define do
    required :country, :string
    required :state, :string
    required :city, :string
    required :timezone, :string
    required :latitude, :float
    required :longitude, :float
    required :geo_hash, :string
  end

  # A proxy, VPN, or anonymizer service seen using an address. +name+ is the
  # service tag, such as "BRIGHTDATA", and +type+ its category.
  Provider = Model.define do
    required :name, :string, wire: "provider"
    required :type, :string
    required :last_seen, :unix_time
  end

  # A device type seen behind an address. +os+ is one of OS.
  Device = Model.define do
    required :os, :string, enum: OS
    required :version, :string
    required :last_seen, :unix_time
  end

  # Synthient's assessment of an address. +risk_score+ runs from 0 to 100.
  # +categories+ and +behavior+ are open sets of tags. An empty +providers+
  # list does not mean the address is clean.
  Intelligence = Model.define do
    required :risk_score, :integer
    required :categories, [:string]
    required :behavior, [:string]
    required :providers, [Provider]
    required :devices, [Device]
  end

  # The intelligence Synthient holds for an IP address. +network+,
  # +location+, and +intelligence+ are nil when the API has no data for them.
  IPInfo = Model.define do
    required :ip, :ip
    optional :network, Network
    optional :location, Location
    optional :intelligence, Intelligence
  end
end
