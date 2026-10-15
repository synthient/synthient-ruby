# frozen_string_literal: true

require_relative "test_helper"

class ModelsTest < SynthientTest
  Sample = Synthient::Model.define do
    required :count, :integer
    optional :ratio, :float
    optional :name, :string
    optional :flag, :bool
    optional :seen, :unix_time
    optional :at, :time
    optional :day, :date
    optional :raw, :bytes
    optional :ip, :ip
    optional :tags, [:string]
    optional :grid, [[:integer]]
    optional :labels, { string: :string }
    optional :device, Synthient::Device
    optional :renamed, :string, wire: "wire_name"
  end

  def decode(object)
    Synthient::Model.decode(Sample, { "count" => 1 }.merge(object), "Sample")
  end

  def assert_invalid(object, message)
    error = assert_raises(Synthient::DecodeError, object.inspect) { decode(object) }
    assert_equal message, error.message
  end

  def test_valid_values
    sample = decode(
      "ratio" => 2, "name" => "x", "flag" => false, "seen" => 1_778_187_600, "at" => "2026-09-28T19:04:52+02:00",
      "day" => "2026-05-07", "raw" => "AAH/", "ip" => "2001:db8::1", "tags" => ["a"], "grid" => [[1, 2], []],
      "labels" => { "Host" => "x" }, "device" => { "os" => "iOS", "version" => "18", "last_seen" => 0 },
      "wire_name" => "y", "unknown" => { "ignored" => true }
    )

    assert_in_delta 2.0, sample.ratio
    assert_kind_of Float, sample.ratio
    refute sample.flag
    assert_equal Time.at(1_778_187_600, in: "UTC"), sample.seen
    assert_predicate sample.seen, :utc?
    assert_equal Time.utc(2026, 9, 28, 17, 4, 52), sample.at
    assert_equal Date.new(2026, 5, 7), sample.day
    assert_equal "\x00\x01\xFF".b, sample.raw
    assert_equal IPAddr.new("2001:db8::1"), sample.ip
    assert_equal [[1, 2], []], sample.grid
    assert_equal({ "Host" => "x" }, sample.labels)
    assert_equal Time.at(0, in: "UTC"), sample.device.last_seen
    assert_equal "y", sample.renamed
  end

  def test_milliseconds_and_seconds
    assert_equal Time.at(999_999_999_999, in: "UTC"), decode("seen" => 999_999_999_999).seen
    assert_equal Time.at(1_778_200_137, 487, :millisecond, in: "UTC"), decode("seen" => 1_778_200_137_487).seen
  end

  def test_invalid_values
    {
      { "count" => nil } => "Sample.count is required",
      { "count" => "1" } => "Sample.count is not a valid integer",
      { "count" => 1.0 } => "Sample.count is not a valid integer",
      { "count" => true } => "Sample.count is not a valid integer",
      { "ratio" => "1.5" } => "Sample.ratio is not a valid float",
      { "ratio" => Float::INFINITY } => "Sample.ratio is not a valid float",
      { "name" => 5 } => "Sample.name is not a valid string",
      { "flag" => "true" } => "Sample.flag is not a valid bool",
      { "flag" => 0 } => "Sample.flag is not a valid bool",
      { "seen" => "1778187600" } => "Sample.seen is not a valid unix time",
      { "seen" => 1.5 } => "Sample.seen is not a valid unix time",
      { "at" => "2026-09-28" } => "Sample.at is not a valid time",
      { "day" => "2026-02-30" } => "Sample.day is not a valid date",
      { "day" => "2026-5-7" } => "Sample.day is not a valid date",
      { "raw" => "not base64!" } => "Sample.raw is not a valid bytes",
      { "ip" => "10.0.0.0/8" } => "Sample.ip is not a valid ip",
      { "ip" => "nope" } => "Sample.ip is not a valid ip",
      { "tags" => "a" } => "Sample.tags is not a valid array",
      { "tags" => ["a", 1] } => "Sample.tags[1] is not a valid string",
      { "tags" => [nil] } => "Sample.tags[0] is not a valid string",
      { "grid" => [[1, "2"]] } => "Sample.grid[0][1] is not a valid integer",
      { "labels" => { "a" => 1 } } => "Sample.labels is not a valid string",
      { "labels" => [] } => "Sample.labels is not a valid hash",
      { "device" => [] } => "Sample.device must be an object",
      { "device" => { "os" => "iOS" } } => "Sample.device.version is required"
    }.each { |object, message| assert_invalid(object, message) }
  end

  def test_absent_and_null_optional_fields
    sample = decode("name" => nil)

    assert_nil sample.name
    assert_nil sample.device
  end

  def test_errors_do_not_include_values
    error = assert_raises(Synthient::DecodeError) { decode("count" => "secret-value") }

    refute_includes error.message, "secret-value"
  end

  def test_models_are_immutable
    sample = decode("tags" => ["a"], "labels" => { "a" => "b" }, "name" => "x")

    assert_predicate sample, :frozen?
    assert_predicate sample.tags, :frozen?
    assert_predicate sample.labels, :frozen?
    assert_predicate sample.name, :frozen?
    refute_respond_to sample, :count=
    assert_raises(FrozenError) { sample.tags << "b" }
  end

  def test_construction_and_with
    device = Synthient::Device.new(os: "iOS", version: "18", last_seen: Time.at(0))

    assert_equal "17", device.with(version: "17").version
    assert_nil Synthient::Network.new(asn: 1, isp: "x", type: "MOBILE").org
    assert_raises(ArgumentError) { Synthient::Network.new(asn: 1) }
    provider = Synthient::Provider.new(name: "BRIGHTDATA", type: "X", last_seen: nil)

    assert_equal({ name: "BRIGHTDATA", type: "X", last_seen: nil }, provider.to_h)
  end

  def test_enum_values_survive_unknown_values
    network = Synthient::Model.decode(Synthient::Network, { "asn" => 1, "isp" => "x", "type" => "SPACE_STATION" })

    assert_equal "SPACE_STATION", network.type
  end
end
