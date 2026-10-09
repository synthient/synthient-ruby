# frozen_string_literal: true

require_relative "test_helper"

begin
  require "synthient/grpcschema"
rescue LoadError => e
  raise if ENV.key?("SYNTHIENT_REQUIRE_GRPC")

  warn "skipping grpcschema tests: #{e.message}"
end

return unless defined?(Synthient::GRPCSchema)

class GRPCSchemaTest < SynthientTest
  Proto = Google::Protobuf
  Request = Synthient::GRPCSchema::MESSAGES["ServerReflectionRequest"]
  Response = Synthient::GRPCSchema::MESSAGES["ServerReflectionResponse"]

  def self.file(name, dependency: [], service: nil, message: nil)
    Proto::FileDescriptorProto.new(
      name:, package: "test", syntax: "proto3", dependency:,
      message_type: message ? [Proto::DescriptorProto.new(name: message)] : [],
      service: service ? [Proto::ServiceDescriptorProto.new(name: service)] : []
    )
  end

  FILES = {
    "test/base.proto" => file("test/base.proto", message: "Base"),
    "test/mid.proto" => file("test/mid.proto", dependency: ["test/base.proto"], message: "Mid"),
    "test/greeter.proto" => file("test/greeter.proto", dependency: ["test/mid.proto", "test/base.proto"], service: "Greeter"),
    "test/orphan.proto" => file("test/orphan.proto", dependency: ["test/missing.proto"], service: "Orphan")
  }.freeze

  SYMBOLS = {
    "test.Greeter" => "test/greeter.proto", "test.Base" => "test/base.proto", "test.Orphan" => "test/orphan.proto"
  }.freeze

  class ReflectionService
    include GRPC::GenericService

    self.marshal_class_method = :encode
    self.unmarshal_class_method = :decode
    self.service_name = "grpc.reflection.v1.ServerReflection"
    rpc :ServerReflectionInfo, stream(Request), stream(Response)
  end

  # A reflection service that answers from FILES, records the requests and
  # metadata it sees, and can be slowed down.
  class FakeReflection < ReflectionService
    attr_reader :keys, :requests
    attr_accessor :services, :delay

    def initialize
      super
      @keys = Queue.new
      @requests = Queue.new
      @services = ["test.Greeter", "test.Orphan", "grpc.reflection.v1.ServerReflection", " "]
      @delay = 0
    end

    def server_reflection_info(requests, call)
      @keys << call.metadata["x-api-key"]
      Enumerator.new do |responses|
        requests.each do |request|
          sleep @delay
          @requests << request
          responses << answer(request)
        end
      end
    end

    def answer(request)
      case request.message_request
      when :list_services
        Response.new(list_services_response: { service: @services.map { |name| { name: } } })
      when :file_containing_symbol
        file = SYMBOLS[request.file_containing_symbol]
        return Response.new(error_response: { error_code: 5, error_message: "symbol not found" }) unless file

        descriptors(file)
      when :file_by_filename
        descriptors(FILES.key?(request.file_by_filename) ? request.file_by_filename : "test/base.proto")
      end
    end

    def descriptors(name)
      Response.new(file_descriptor_response: { file_descriptor_proto: [Proto::FileDescriptorProto.encode(FILES[name])] })
    end
  end

  def setup
    @reflection = FakeReflection.new
    @grpc = GRPC::RpcServer.new
    @port = @grpc.add_http2_port("127.0.0.1:0", :this_port_is_insecure)
    @grpc.handle(@reflection)
    @thread = Thread.new { @grpc.run }
    @grpc.wait_till_running
  end

  def teardown
    @grpc.stop
    @thread.join
    super
  end

  def fetch(**)
    Synthient::GRPCSchema.fetch(api_key: "grpc-key", endpoint: "127.0.0.1:#{@port}", plaintext: true, timeout: 5,
                                **)
  end

  def test_fetches_every_service_with_dependencies
    @reflection.services = ["test.Greeter", "grpc.reflection.v1.ServerReflection", " "]
    schema = fetch

    assert_equal "127.0.0.1:#{@port}", schema.endpoint
    assert_equal ["test.Greeter"], schema.symbols
    assert_equal %w[test/base.proto test/mid.proto test/greeter.proto], schema.descriptor_set.file.map(&:name)
    assert_equal "grpc-key", @reflection.keys.pop
    assert_equal "127.0.0.1", @reflection.requests.pop.host
  end

  def test_include_reflection
    @reflection.services = ["grpc.reflection.v1.ServerReflection"]

    assert_raises(Synthient::GRPCSchema::SchemaError) { fetch }
    error = assert_raises(Synthient::GRPCSchema::SchemaError) { fetch(include_reflection: true) }

    assert_equal 5, error.code
  end

  def test_symbols_are_cleaned
    schema = fetch(symbols: [" test.Base ", "", "test.Base"])

    assert_equal ["test.Base"], schema.symbols
    assert_equal ["test/base.proto"], schema.descriptor_set.file.map(&:name)
  end

  def test_unknown_symbol
    error = assert_raises(Synthient::GRPCSchema::SchemaError) { fetch(symbols: ["test.Nope"]) }

    assert_equal GRPC::Core::StatusCodes::NOT_FOUND, error.code
    assert_equal "symbol not found", error.message
    assert_match(/No protobuf schema found/, Synthient::GRPCSchema.explain(error))
  end

  def test_missing_dependency
    error = assert_raises(Synthient::GRPCSchema::SchemaError) { fetch(symbols: ["test.Orphan"]) }

    assert_equal "reflection did not return dependency test/missing.proto", error.message
    assert_nil error.code
  end

  def test_stream_ends_while_fetching_dependency
    responses = [@reflection.descriptors("test/orphan.proto")].each
    original = GRPC::ClientStub.instance_method(:bidi_streamer)
    GRPC::ClientStub.define_method(:bidi_streamer) { |*_, **_| responses }
    error = assert_raises(Synthient::GRPCSchema::SchemaError) { fetch(symbols: ["test.Orphan"]) }

    assert_equal "reflection stream ended early", error.message
    assert_nil error.code
  ensure
    GRPC::ClientStub.define_method(:bidi_streamer, original)
  end

  def test_no_api_key_sends_no_metadata
    Synthient::GRPCSchema.fetch(api_key: " ", endpoint: "127.0.0.1:#{@port}", plaintext: true, symbols: ["test.Base"])

    assert_nil @reflection.keys.pop
  end

  def test_timeout
    @reflection.delay = 2
    error = assert_raises(Synthient::GRPCSchema::SchemaError) { fetch(timeout: 0.3) }

    assert_equal GRPC::Core::StatusCodes::DEADLINE_EXCEEDED, error.code
  end

  def test_unreachable_endpoint
    port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
    error = assert_raises(Synthient::GRPCSchema::SchemaError) do
      Synthient::GRPCSchema.fetch(api_key: "k", endpoint: "127.0.0.1:#{port}", plaintext: true, timeout: 2)
    end

    assert_includes [GRPC::Core::StatusCodes::UNAVAILABLE, GRPC::Core::StatusCodes::DEADLINE_EXCEEDED], error.code
  end

  def test_normalize_endpoint
    {
      "" => ["grpc.synthient.com:443", "grpc.synthient.com"],
      nil => ["grpc.synthient.com:443", "grpc.synthient.com"],
      "example.com" => ["example.com:443", "example.com"],
      "example.com:8443" => ["example.com:8443", "example.com"],
      "example.com/" => ["example.com:443", "example.com"],
      "grpc://example.com:50051" => ["example.com:50051", "example.com"],
      "grpc://example.com" => ["example.com:443", "example.com"],
      "https://example.com/" => ["example.com:443", "example.com"],
      "::1" => ["[::1]:443", "::1"],
      "[::1]" => ["[::1]:443", "::1"],
      "[::1]:50051" => ["[::1]:50051", "::1"],
      " 127.0.0.1:50051 " => ["127.0.0.1:50051", "127.0.0.1"]
    }.each do |raw, expected|
      assert_equal expected, Synthient::GRPCSchema.normalize_endpoint(raw), raw.inspect
    end
    assert_raises(ArgumentError) { Synthient::GRPCSchema.normalize_endpoint("grpc://") }
    assert_raises(ArgumentError) { Synthient::GRPCSchema.normalize_endpoint("grpc://bad host") }
  end

  def test_explain
    {
      16 => /API key/, 7 => /permission/, 5 => /symbol/, 12 => /reflection/, 14 => /reach/, 4 => /Timed out/
    }.each do |code, pattern|
      assert_match pattern, Synthient::GRPCSchema.explain(Synthient::GRPCSchema::SchemaError.new("x", code:))
    end
    assert_nil Synthient::GRPCSchema.explain(Synthient::GRPCSchema::SchemaError.new("x", code: 2))
    assert_nil Synthient::GRPCSchema.explain(Synthient::GRPCSchema::SchemaError.new("x"))
    assert_match(/API key/, Synthient::GRPCSchema.explain(GRPC::Unauthenticated.new("no")))
    assert_nil Synthient::GRPCSchema.explain(RuntimeError.new("x"))
  end

  def test_reflection_wire_format
    assert_equal "\x0a\x01h\x3a\x00".b, Request.encode(Request.new(host: "h", list_services: ""))
    assert_equal "\x1a\x01f".b, Request.encode(Request.new(file_by_filename: "f"))
    assert_equal "\x22\x01s".b, Request.encode(Request.new(file_containing_symbol: "s"))
    error = Response.decode("\x3a\x07\x08\x05\x12\x03bad".b).error_response

    assert_equal [5, "bad"], [error.error_code, error.error_message]
    assert_equal ["s"], Response.decode("\x32\x05\x0a\x03\x0a\x01s".b).list_services_response.service.map(&:name)
    assert_equal ["d"], Response.decode("\x22\x03\x0a\x01d".b).file_descriptor_response.file_descriptor_proto.to_a
    assert_equal "v", Response.decode("\x0a\x01v".b).valid_host
  end

  def test_no_global_reflection_constants
    refute defined?(Grpc::Reflection)
  end
end
