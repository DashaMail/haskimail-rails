# frozen_string_literal: true

module Haskimail
  # Wraps a credential so that it cannot leak through #inspect, #to_s,
  # string interpolation, JSON/ActiveSupport serialization or error trackers
  # that dump instance variables. Use #reveal to read the real value.
  class Secret
    REDACTED = "[REDACTED]"

    def initialize(value)
      @value = value.to_s.dup.freeze
      freeze
    end

    def reveal
      @value
    end

    def empty?
      @value.empty?
    end

    def ==(other)
      other.is_a?(Secret) && Webhooks.secure_compare(reveal, other.reveal)
    end
    alias eql? ==

    def hash
      [self.class, @value].hash
    end

    def inspect
      "#<#{self.class.name} #{Util.redact(@value)}>"
    end

    def to_s = REDACTED
    def as_json(*) = REDACTED
    def to_json(*) = REDACTED.to_json
  end
end
