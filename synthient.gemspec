# frozen_string_literal: true

require_relative "lib/synthient/version"

Gem::Specification.new do |spec|
  spec.name = "synthient"
  spec.version = Synthient::VERSION
  spec.authors = ["Synthient"]
  spec.summary = "The official Ruby client for the Synthient API"
  spec.description = "IP and domain intelligence, account details, and real-time and bulk data feeds " \
                     "from the Synthient API."
  spec.homepage = "https://github.com/synthient/synthient-ruby"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "documentation_uri" => "https://rubydoc.info/gems/synthient",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "sig/manifest.yaml", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
