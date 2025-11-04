# frozen_string_literal: true

require "anthropic"

# Initialize Anthropic gem with configuration
Anthropic.setup do |config|
  config.api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
end
