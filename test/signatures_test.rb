# frozen_string_literal: true

require_relative "test_helper"
require_relative "../scripts/models_rbs"

class SignaturesTest < SynthientTest
  def test_model_signatures_are_current
    path = File.expand_path("../sig/synthient/models.rbs", __dir__)

    assert_equal File.read(path), ModelsRBS.render, "run `bundle exec rake sig`"
  end
end
