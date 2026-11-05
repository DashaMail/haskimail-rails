# frozen_string_literal: true

require "uri"

module Haskimail
  # Global and per-client settings.
  #
  #   Haskimail.configure do |config|
  #     config.server_token  = Rails.application.credentials.dig(:haskimail, :server_token)
  #     config.account_token = Rails.application.credentials.dig(:haskimail, :account_token)
  #     config.default_message_stream = "2081"
  #   end
  class Configuration
    DEFAULT_BASE_URL = "https://api.haskimail.ru"

    SETTINGS = %i[
      server_token account_token base_url open_timeout read_timeout write_timeout
      max_retries retry_base_delay retry_max_delay logger default_message_stream
      user_agent_suffix persistent_connections
    ].freeze

    attr_accessor(*SETTINGS)

    def initialize
      @server_token = ENV.fetch("HASKIMAIL_SERVER_TOKEN", nil)
      @account_token = ENV.fetch("HASKIMAIL_ACCOUNT_TOKEN", nil)
      @base_url = DEFAULT_BASE_URL
      @open_timeout = 5
      @read_timeout = 30
      @write_timeout = 30
      @max_retries = 2
      @retry_base_delay = 0.5
      @retry_max_delay = 8.0
      @logger = nil
      @default_message_stream = nil
      @user_agent_suffix = nil
      @persistent_connections = true
    end

    # Returns a copy with the given settings overridden; the receiver is untouched.
    def merge(overrides)
      unknown = overrides.keys.map(&:to_sym) - SETTINGS
      raise ArgumentError, "Unknown Haskimail setting(s): #{unknown.join(', ')}" if unknown.any?

      copy = dup
      overrides.each { |key, value| copy.public_send(:"#{key}=", value) }
      copy
    end

    def to_h
      SETTINGS.to_h { |key| [key, public_send(key)] }
    end

    # Validates connection settings and returns the parsed base URI.
    def base_uri
      uri = URI.parse(base_url.to_s)
      unless uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty?
        raise ConfigurationError, "base_url must be an absolute https:// URL, got #{base_url.inspect}"
      end
      raise ConfigurationError, "base_url must not contain credentials" if uri.userinfo

      uri
    rescue URI::InvalidURIError => e
      raise ConfigurationError, "Invalid base_url: #{e.message}"
    end

    SECRET_SETTINGS = %i[server_token account_token].freeze

    def inspect
      attrs = to_h.map do |key, value|
        value = Util.redact(value) if SECRET_SETTINGS.include?(key)
        "#{key}=#{value.inspect}"
      end
      "#<#{self.class.name} #{attrs.join(', ')}>"
    end
    alias to_s inspect

    # Safe for logs and error trackers: tokens are redacted.
    def as_json(*)
      to_h.except(:logger).to_h do |key, value|
        [key.to_s, SECRET_SETTINGS.include?(key) && value ? Secret::REDACTED : value]
      end
    end

    def to_json(*args)
      as_json.to_json(*args)
    end
  end
end
