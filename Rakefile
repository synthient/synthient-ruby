# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

desc "Generate sig/synthient/models.rbs from the model definitions"
task :sig do
  require_relative "scripts/models_rbs"
  File.write("sig/synthient/models.rbs", ModelsRBS.render)
end

task default: :test
