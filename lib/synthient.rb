# frozen_string_literal: true

require "date"
require "ipaddr"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"
require "zlib"

# The official Ruby client for the Synthient API: IP and domain intelligence,
# account details, and real-time and bulk data feeds. Start with
# Synthient::Client.
module Synthient
  DEFAULT_BASE_URL = "https://api.synthient.com/api/v4"
end

require_relative "synthient/version"
require_relative "synthient/errors"
require_relative "synthient/response_metadata"
require_relative "synthient/model"
require_relative "synthient/models/lookup"
require_relative "synthient/models/domain"
require_relative "synthient/models/account"
require_relative "synthient/models/export"
require_relative "synthient/models/events"
require_relative "synthient/transport"
require_relative "synthient/feed"
require_relative "synthient/client"
