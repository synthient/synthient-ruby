# frozen_string_literal: true

require "synthient"

begin
  require "grpc"
  require "google/protobuf"
  require "google/protobuf/descriptor_pb"
rescue LoadError => e
  raise LoadError, "synthient/grpcschema needs the grpc and google-protobuf gems: " \
                   "add them to your Gemfile or run `gem install grpc google-protobuf` (#{e.message})"
end

module Synthient
  # Fetches the protobuf schema of the Synthient gRPC API using gRPC server
  # reflection. Load it with <tt>require "synthient/grpcschema"</tt>; it needs
  # the grpc and google-protobuf gems, which the synthient gem does not
  # depend on.
  #
  # @example
  #   schema = Synthient::GRPCSchema.fetch
  #   schema.descriptor_set.file.each { |file| puts file.name }
  module GRPCSchema
    DEFAULT_ENDPOINT = "grpc.synthient.com:443"
    MAX_MESSAGE_SIZE = 32 << 20

    EXPLANATIONS = {
      GRPC::Core::StatusCodes::UNAUTHENTICATED => "Missing or invalid API key.",
      GRPC::Core::StatusCodes::PERMISSION_DENIED => "This API key does not have permission to inspect gRPC schemas.",
      GRPC::Core::StatusCodes::NOT_FOUND =>
        "No protobuf schema found for the requested symbol. Fetch without symbols to list the available services.",
      GRPC::Core::StatusCodes::UNIMPLEMENTED => "The gRPC endpoint does not expose server reflection.",
      GRPC::Core::StatusCodes::UNAVAILABLE =>
        "Could not reach the gRPC endpoint. Check the address, network access, and TLS settings.",
      GRPC::Core::StatusCodes::DEADLINE_EXCEEDED =>
        "Timed out reading protobuf schemas from gRPC reflection. Use a longer timeout."
    }.freeze

    # The result of GRPCSchema.fetch. +endpoint+ is the normalized address
    # that was queried, +symbols+ the names that were resolved, and
    # +descriptor_set+ a Google::Protobuf::FileDescriptorSet holding the
    # resolved files in dependency order, each after the files it imports.
    Schema = Data.define(:endpoint, :symbols, :descriptor_set)

    # A failed schema fetch. +code+ is the gRPC status code, or nil when the
    # server's reflection responses were unusable.
    class SchemaError < Synthient::Error
      attr_reader :code

      def initialize(message = nil, code: nil)
        super(message)
        @code = code
      end
    end

    # The reflection v1 messages, built in a private descriptor pool so they
    # never clash with an application's own generated reflection classes.
    # @api private
    MESSAGES = begin
      proto = Google::Protobuf
      field = lambda do |name, number, type, label: :LABEL_OPTIONAL, type_name: nil, oneof: nil|
        proto::FieldDescriptorProto.new(name:, number:, type:, label:, oneof_index: oneof, json_name: name,
                                        type_name: type_name && ".grpc.reflection.v1.#{type_name}")
      end
      file = proto::FileDescriptorProto.new(
        name: "synthient/grpc_reflection_v1.proto", package: "grpc.reflection.v1", syntax: "proto3",
        message_type: [
          proto::DescriptorProto.new(
            name: "ServerReflectionRequest", oneof_decl: [proto::OneofDescriptorProto.new(name: "message_request")],
            field: [
              field.call("host", 1, :TYPE_STRING),
              field.call("file_by_filename", 3, :TYPE_STRING, oneof: 0),
              field.call("file_containing_symbol", 4, :TYPE_STRING, oneof: 0),
              field.call("list_services", 7, :TYPE_STRING, oneof: 0)
            ]
          ),
          proto::DescriptorProto.new(
            name: "ServerReflectionResponse", oneof_decl: [proto::OneofDescriptorProto.new(name: "message_response")],
            field: [
              field.call("valid_host", 1, :TYPE_STRING),
              field.call("original_request", 2, :TYPE_MESSAGE, type_name: "ServerReflectionRequest"),
              field.call("file_descriptor_response", 4, :TYPE_MESSAGE, type_name: "FileDescriptorResponse", oneof: 0),
              field.call("list_services_response", 6, :TYPE_MESSAGE, type_name: "ListServiceResponse", oneof: 0),
              field.call("error_response", 7, :TYPE_MESSAGE, type_name: "ErrorResponse", oneof: 0)
            ]
          ),
          proto::DescriptorProto.new(
            name: "FileDescriptorResponse",
            field: [field.call("file_descriptor_proto", 1, :TYPE_BYTES, label: :LABEL_REPEATED)]
          ),
          proto::DescriptorProto.new(
            name: "ListServiceResponse",
            field: [field.call("service", 1, :TYPE_MESSAGE, label: :LABEL_REPEATED, type_name: "ServiceResponse")]
          ),
          proto::DescriptorProto.new(name: "ServiceResponse", field: [field.call("name", 1, :TYPE_STRING)]),
          proto::DescriptorProto.new(
            name: "ErrorResponse",
            field: [field.call("error_code", 1, :TYPE_INT32), field.call("error_message", 2, :TYPE_STRING)]
          )
        ]
      )
      pool = proto::DescriptorPool.new
      pool.add_serialized_file(proto::FileDescriptorProto.encode(file))
      file.message_type.to_h { |message| [message.name, pool.lookup("grpc.reflection.v1.#{message.name}").msgclass] }.freeze
    end

    # Fetches the protobuf files that define +symbols+, or every service the
    # server lists when +symbols+ is empty, along with all of their imports.
    #
    # @param api_key [String, nil] sent as x-api-key metadata unless blank;
    #   by default from SYNTHIENT_API_KEY
    # @param endpoint [String] host:port, a bare host (port 443 is assumed), or
    #   a grpc:// or https:// URL
    # @param plaintext [Boolean] disables TLS, for local development servers
    # @param include_reflection [Boolean] includes the reflection service
    #   itself when listing services
    # @param symbols [Array<String>] fully qualified service or message names
    # @param timeout [Numeric] seconds the whole fetch may take
    # @return [Schema]
    # @raise [SchemaError] with the gRPC status code when the server rejects a request
    def self.fetch(api_key: ENV.fetch("SYNTHIENT_API_KEY", nil), endpoint: DEFAULT_ENDPOINT, plaintext: false,
                   include_reflection: false, symbols: [], timeout: 30)
      raise ArgumentError, "timeout must be a positive number of seconds" unless timeout.is_a?(Numeric) && timeout.positive?

      endpoint, host = normalize_endpoint(endpoint)
      credentials = plaintext ? :this_channel_is_insecure : GRPC::Core::ChannelCredentials.new
      channel = GRPC::Core::Channel.new(endpoint, { "grpc.max_receive_message_length" => MAX_MESSAGE_SIZE }, credentials)
      stub = GRPC::ClientStub.new(endpoint, credentials, channel_override: channel)
      requests = Queue.new
      metadata = api_key.to_s.strip.empty? ? {} : { "x-api-key" => api_key.strip }
      responses = stub.bidi_streamer(
        "/grpc.reflection.v1.ServerReflection/ServerReflectionInfo",
        Enumerator.new { |stream| while (request = requests.pop) do stream << request end },
        MESSAGES["ServerReflectionRequest"].method(:encode), MESSAGES["ServerReflectionResponse"].method(:decode),
        deadline: Time.now + timeout, metadata:
      )
      exchange = lambda do |request|
        requests << MESSAGES["ServerReflectionRequest"].new(host:, **request)
        response = responses.next
        error = response.error_response
        raise SchemaError.new(error.error_message, code: error.error_code) if error

        response
      end

      symbols = symbols.map { |symbol| symbol.to_s.strip }.reject(&:empty?).uniq
      if symbols.empty?
        list = exchange.call(list_services: "").list_services_response
        raise SchemaError, "reflection response has no service list" unless list

        symbols = list.service.map { |service| service.name.strip }.reject(&:empty?)
        symbols = symbols.reject { |name| name.start_with?("grpc.reflection.") } unless include_reflection
        symbols.sort!
      end
      raise SchemaError, "server lists no services" if symbols.empty?

      files = {}
      add_files = lambda do |response|
        list = response.file_descriptor_response
        raise SchemaError, "reflection response has no file descriptors" unless list

        list.file_descriptor_proto.each do |data|
          file = Google::Protobuf::FileDescriptorProto.decode(data)
          raise SchemaError, "reflection returned a file descriptor without a name" if file.name.empty?

          files[file.name] ||= file
        end
      end
      symbols.each { |symbol| add_files.call(exchange.call(file_containing_symbol: symbol)) }
      loop do
        missing = files.each_value.flat_map { |file| file.dependency.to_a }.uniq.reject { |name| files.key?(name) }.sort
        break if missing.empty?

        missing.each do |name|
          add_files.call(exchange.call(file_by_filename: name))
          raise SchemaError, "reflection did not return dependency #{name}" unless files.key?(name)
        end
      end

      ordered = []
      visited = Set.new
      visit = lambda do |name|
        next unless files.key?(name) && visited.add?(name)

        files[name].dependency.to_a.sort.each { |dependency| visit.call(dependency) }
        ordered << files[name]
      end
      files.keys.sort.each { |name| visit.call(name) }
      Schema.new(endpoint:, symbols: symbols.freeze,
                 descriptor_set: Google::Protobuf::FileDescriptorSet.new(file: ordered))
    rescue GRPC::BadStatus => e
      raise SchemaError.new(e.details, code: e.code)
    rescue Google::Protobuf::ParseError
      raise SchemaError, "reflection returned an invalid file descriptor"
    rescue StopIteration
      raise SchemaError, "reflection stream ended early"
    ensure
      requests&.close
      channel&.close
    end

    # Converts an endpoint to host:port form, and returns it with the host
    # name used for TLS verification.
    #
    # @return [Array(String, String)] the endpoint and its host
    # @raise [ArgumentError] if the endpoint is empty or not a valid URL
    def self.normalize_endpoint(raw)
      raw = raw.to_s.strip
      raw = DEFAULT_ENDPOINT if raw.empty?
      if raw.include?("://")
        uri = URI.parse(raw)
        raw = uri.port ? "#{uri.host}:#{uri.port}" : uri.host.to_s
      end
      raw = raw.delete_suffix("/")
      raise ArgumentError, "empty gRPC endpoint" if raw.empty?

      if raw.start_with?("[")
        host, port = raw.delete_prefix("[").split("]", 2)
        return port.to_s.start_with?(":") ? [raw, host] : ["[#{host}]:443", host]
      end
      return [raw, raw.split(":").first] if raw.count(":") == 1

      raw.include?(":") ? ["[#{raw}]:443", raw] : ["#{raw}:443", raw]
    rescue URI::InvalidURIError
      raise ArgumentError, "invalid gRPC endpoint #{raw.inspect}"
    end

    # Returns a human-readable explanation of a common fetch failure, or nil.
    #
    # @param error [SchemaError, GRPC::BadStatus]
    # @return [String, nil]
    def self.explain(error)
      EXPLANATIONS[error.code] if error.respond_to?(:code)
    end
  end
end
