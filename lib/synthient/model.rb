# frozen_string_literal: true

module Synthient
  # Defines the response models and decodes API JSON into them.
  #
  # Models are Data classes. Decoding is strict: a field the API schema
  # requires must be present, non-null, and of its declared type. Optional
  # fields may be absent or null and become nil. Unknown fields are ignored so
  # that additive API changes don't break decoding.
  #
  # @api private
  module Model
    Field = Data.define(:name, :wire, :type, :required, :enum)

    # Collects the fields declared in a Model.define block.
    class Builder
      attr_reader :fields

      def initialize
        @fields = []
      end

      def required(name, type, wire: name.to_s, enum: nil)
        @fields << Field.new(name:, wire:, type:, required: true, enum:)
      end

      def optional(name, type, wire: name.to_s, enum: nil)
        @fields << Field.new(name:, wire:, type:, required: false, enum:)
      end
    end

    # Builds a Data class from +required+ and +optional+ field declarations.
    # Optional members default to nil.
    def self.define(&)
      builder = Builder.new
      builder.instance_eval(&)
      fields = builder.fields.freeze
      defaults = fields.reject(&:required).to_h { |field| [field.name, nil] }.freeze
      Data.define(*fields.map(&:name)) do
        define_singleton_method(:fields) { fields }
        define_method(:initialize) { |**attrs| super(**defaults, **attrs) }
      end
    end

    def self.decode(model, object, path = model.name.delete_prefix("Synthient::"))
      raise DecodeError, "#{path} must be an object" unless object.is_a?(Hash)

      attrs = model.fields.to_h do |field|
        value = object[field.wire]
        field_path = "#{path}.#{field.wire}"
        raise DecodeError, "#{field_path} is required" if value.nil? && field.required

        [field.name, value.nil? ? nil : decode_value(field.type, value, field_path)]
      end
      model.new(**attrs)
    end

    def self.decode_value(type, value, path)
      case type
      when :integer
        return value if value.is_a?(Integer)
      when :float
        return value.to_f if (value.is_a?(Integer) || value.is_a?(Float)) && value.to_f.finite?
      when :string
        return value if value.is_a?(String)
      when :bool
        return value if [true, false].include?(value)
      when :unix_time
        if value.is_a?(Integer)
          return Time.at(value, in: "UTC") if value < 1_000_000_000_000

          return Time.at(value / 1000, value % 1000, :millisecond, in: "UTC")
        end
      when :time
        return Time.iso8601(value) if value.is_a?(String)
      when :date
        return Date.iso8601(value) if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      when :bytes
        return value.unpack1("m0").freeze if value.is_a?(String)
      when :ip
        return IPAddr.new(value) if value.is_a?(String) && !value.include?("/") && !value.include?("%")
      when Array
        if value.is_a?(Array)
          return value.each_with_index.map { |item, index| decode_value(type.first, item, "#{path}[#{index}]") }.freeze
        end
      when Hash
        return value.transform_values { |item| decode_value(type.values.first, item, path) }.freeze if value.is_a?(Hash)
      else
        return decode(type, value, path)
      end
      raise DecodeError, "#{path} is not a valid #{type.is_a?(Symbol) ? type.to_s.tr("_", " ") : type.class.name.downcase}"
    rescue ArgumentError
      raise DecodeError, "#{path} is not a valid #{type.to_s.tr("_", " ")}"
    end
  end
end
