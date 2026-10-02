# frozen_string_literal: true

require "synthient"
require_relative "../support/server"

loaded = $LOADED_FEATURES.find { |path| path.end_with?("/synthient.rb") }
abort "loaded #{loaded}, not the installed gem" unless loaded.start_with?(File.realpath(ENV.fetch("GEM_HOME")))

body = '{"ip":"8.8.8.8","intelligence":{"risk_score":3,"categories":[],"behavior":[],"providers":[],"devices":[]}}'
server = TestServer.new { [200, { "content-type" => "application/json" }, body] }
client = Synthient::Client.new(api_key: "key", base_url: server.url)
info = client.lookup_ip("8.8.8.8")
client.close
server.close
abort "unexpected risk score" unless info.intelligence.risk_score == 3
puts "plain consumer: ok"
