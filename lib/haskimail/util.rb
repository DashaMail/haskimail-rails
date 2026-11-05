# frozen_string_literal: true

require "date"
require "time"
require "erb"

module Haskimail
  # Small, dependency-free helpers shared across the library.
  module Util
    MOSCOW_OFFSET = "+03:00" # Moscow has no DST since 2014; the API works in MSK.

    module_function

    # "8f3e0c7a-5b2d-..." -> "8f3e…2a94". Never prints a full secret.
    def redact(secret)
      return nil if secret.nil?

      str = secret.to_s
      return "[REDACTED]" if str.length < 12

      "#{str[0, 4]}…#{str[-4, 4]}"
    end

    # Encodes a single path segment so that IDs and template aliases cannot
    # change the request path ("/", "?", "#", "..", spaces, Cyrillic, ...).
    def escape_path_segment(value)
      segment = value.to_s
      raise ArgumentError, "Path parameter must not be blank" if segment.strip.empty?
      raise ArgumentError, "Invalid path parameter: #{segment.inspect}" if %w[. ..].include?(segment)

      ERB::Util.url_encode(segment)
    end

    # Header values must not contain CR/LF (header injection) or be blank.
    def validate_token!(token, name)
      str = token.to_s
      raise ConfigurationError, "#{name} is not set" if str.strip.empty?
      raise ConfigurationError, "#{name} contains illegal characters" if str.match?(/[\r\n\0]/)

      str
    end

    # Date-only API filter: "2026-10-01" (Moscow date).
    def format_date(value)
      case value
      when nil then nil
      when String then validate_date_string!(value, date_only: true)
      when DateTime, Time then to_moscow(value).strftime("%Y-%m-%d")
      when Date then value.strftime("%Y-%m-%d")
      else
        return format_date(value.to_time) if value.respond_to?(:to_time)

        raise ArgumentError, "Expected a Date, Time or String, got #{value.class}"
      end
    end

    # Date-time API filter: "2026-10-01 12:00:00" (or with "T" for inbound search).
    def format_datetime(value, separator: " ")
      case value
      when nil then nil
      when String then validate_date_string!(value)
      when DateTime, Time then to_moscow(value).strftime("%Y-%m-%d#{separator}%H:%M:%S")
      when Date then value.strftime("%Y-%m-%d")
      else
        return format_datetime(value.to_time, separator: separator) if value.respond_to?(:to_time)

        raise ArgumentError, "Expected a Date, Time or String, got #{value.class}"
      end
    end

    def to_moscow(value)
      value.to_time.getlocal(MOSCOW_OFFSET)
    end

    DATE_STRING = /\A(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?\z/

    # Accepts "YYYY-MM-DD" and, unless date_only, "YYYY-MM-DD HH:MM[:SS]" (or with "T").
    def validate_date_string!(value, date_only: false)
      match = DATE_STRING.match(value)
      valid = match && Date.valid_date?(match[1].to_i, match[2].to_i, match[3].to_i) &&
              (match[4].nil? || (!date_only && match[4].to_i < 24 && match[5].to_i < 60 && match[6].to_i < 60))
      return value if valid

      raise ArgumentError,
            "Invalid date #{value.inspect}, expected #{date_only ? 'YYYY-MM-DD' : 'YYYY-MM-DD[ HH:MM:SS]'}"
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)
    end

    # Drops nil values from a flat hash.
    def compact(hash)
      hash.compact
    end

    def assert_known_keys!(given, allowed, context)
      unknown = given.map(&:to_sym) - allowed
      return if unknown.empty?

      raise ArgumentError, "Unknown #{context} option(s): #{unknown.join(', ')}. Allowed: #{allowed.join(', ')}"
    end

    def assert_range!(name, value, range)
      return if value.nil?
      raise ArgumentError, "#{name} must be an Integer" unless value.is_a?(Integer)
      raise ArgumentError, "#{name} must be within #{range}, got #{value}" unless range.cover?(value)
    end
  end
end
