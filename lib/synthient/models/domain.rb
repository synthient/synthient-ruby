# frozen_string_literal: true

module Synthient
  # Whether a domain had events in the last 24 hours.
  # @deprecated Used only by the deprecated Client#lookup_domain.
  module DomainStatus
    ACTIVE = "active"
    INACTIVE = "inactive"
  end

  # The sentences that describe a domain's activity over the last 30 days.
  # @deprecated Used only by the deprecated Client#lookup_domain.
  module Cadence
    NO_ACTIVITY = "No activity in the last 30 days."
    EVENLY_DISTRIBUTED = "Activity is evenly distributed across the day."
    BUSINESS_HOURS = "Activity follows a weekday business-hours pattern."
    WEEKEND = "Activity follows a weekend pattern."
    BURST_DRIVEN = "Activity is burst-driven with significant peaks."
  end

  # @deprecated Used only by the deprecated Client#lookup_domain.
  DomainStats = Model.define do
    required :events_24h, :integer
    required :total_events_30d, :integer
  end

  # Distinct source addresses seen for a domain. +sparkline_24h+ holds hourly
  # counts for the last 24 hours, oldest first.
  # @deprecated Used only by the deprecated Client#lookup_domain.
  UniqueIPs = Model.define do
    required :value_24h, :integer
    required :value_30d, :integer
    required :sparkline_24h, [:integer]
  end

  # The events and distinct addresses seen for a domain on one day.
  # @deprecated Used only by the deprecated Client#lookup_domain.
  TimeSeriesPoint = Model.define do
    required :date, :unix_time
    required :events, :integer
    required :unique_ips, :integer
  end

  # The autonomous system that sent the most events.
  # @deprecated Used only by the deprecated Client#lookup_domain.
  ASNCount = Model.define do
    required :asn, :integer
    required :events, :integer
  end

  # @deprecated Used only by the deprecated Client#lookup_domain.
  SubdomainCount = Model.define do
    required :subdomain, :string
    required :count, :integer
  end

  # @deprecated Used only by the deprecated Client#lookup_domain.
  PortCount = Model.define do
    required :port, :integer
    required :count, :integer
  end

  # The events and distinct addresses seen from one country.
  # @deprecated Used only by the deprecated Client#lookup_domain.
  CountryCount = Model.define do
    required :country_code, :string
    required :events, :integer
    required :unique_ips, :integer
  end

  # +peak_hour+ and +quiet_hour+ are UTC hours, and +cadence+ is one of
  # Cadence.
  # @deprecated Used only by the deprecated Client#lookup_domain.
  ActivityStats = Model.define do
    required :cadence, :string
    required :median_per_hour, :integer
    required :p95_per_hour, :integer
    required :peak_hour, :integer
    required :quiet_hour, :integer
  end

  # +source_ip+ is the full source address, although the API names it
  # source_ip_masked.
  # @deprecated Used only by the deprecated Client#lookup_domain.
  DomainEvent = Model.define do
    required :timestamp, :unix_time
    required :source_ip, :string, wire: "source_ip_masked"
    required :target_subdomain, :string
    required :country_code, :string
    required :port, :integer
  end

  # The honeypot traffic Synthient has observed for a domain. A domain that
  # was never observed is +inactive+ with zero counts. +top_asn+ is nil when
  # there were no events. +hour_dow_heatmap+ has 7 rows, Monday first, of 24
  # UTC hourly counts.
  # @deprecated Domain lookup was removed from the Synthient API and will stop
  #   working when the endpoint is turned off. It will be removed in the next
  #   major version.
  DomainInfo = Model.define do
    required :domain, :string
    required :status, :string
    required :stats, DomainStats
    required :unique_ips, UniqueIPs
    required :time_series, [TimeSeriesPoint]
    optional :top_asn, ASNCount
    required :top_subdomains, [SubdomainCount]
    required :top_ports, [PortCount]
    required :geo_distribution, [CountryCount]
    required :hour_dow_heatmap, [[:integer]]
    required :activity_stats, ActivityStats
    required :recent_events, [DomainEvent]
  end
end
