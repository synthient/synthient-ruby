# frozen_string_literal: true

# Fetches the protobuf schema of the Synthient gRPC API through server
# reflection and prints its services and files. It needs the grpc and
# google-protobuf gems.
#
#   SYNTHIENT_API_KEY=... bundle exec ruby examples/grpc_schema.rb

require "synthient/grpcschema"

begin
  schema = Synthient::GRPCSchema.fetch
rescue Synthient::GRPCSchema::SchemaError => e
  explanation = Synthient::GRPCSchema.explain(e)
  abort explanation ? "#{explanation} #{e.message}" : e.message
end

puts "endpoint: #{schema.endpoint}"
schema.symbols.each { |symbol| puts "service: #{symbol}" }
schema.descriptor_set.file.each { |file| puts "file: #{file.name} (package #{file.package})" }
