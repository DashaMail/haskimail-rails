# frozen_string_literal: true

require "json"
require "time"

module Haskimail
  module Webhooks
    # A delivery, bounce, spam complaint, open, click or subscription change event.
    class Event
      TYPES = %i[delivered bounced complained opened clicked subscription_change].freeze
      BOUNCE_CATEGORIES = { "hrd" => :hard, "sft" => :soft, "blk" => :blocked, "spm" => :spam }.freeze
      MOSCOW_OFFSET = "+03:00"

      attr_reader :raw

      def initialize(data)
        @raw = data.transform_keys(&:to_s).freeze
      end

      # @return [Symbol] :delivered, :bounced, :complained, :opened, :clicked,
      #   :subscription_change (or the raw value, downcased, for unknown events)
      def type
        @type ||= begin
          value = raw["event"].to_s.downcase
          value == "subscriptionchange" ? :subscription_change : value.to_sym
        end
      end

      TYPES.each do |event_type|
        define_method(:"#{event_type}?") { type == event_type }
      end

      def recipient = string("recipient") || string("email")
      def message_id = raw["message_id"].to_s
      def tag = string("campaign_id")
      def server_id = raw["server_id"]&.to_i
      def stream_id = raw["stream_id"]&.to_s
      def secret = string("secret")

      # Metadata sent with the message. Haskimail delivers it as a JSON string
      # (or an object in some events); always returns a Hash.
      def metadata
        @metadata ||= begin
          value = raw["custom_vars"]
          parsed = value.is_a?(String) && !value.strip.empty? ? JSON.parse(value) : value
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end
      end

      # @return [Time, nil] event time in UTC
      def occurred_at
        @occurred_at ||= if string("event_time_utc")
                           parse_time(raw["event_time_utc"], "+00:00")
                         elsif string("event_time")
                           parse_time(raw["event_time"], MOSCOW_OFFSET)
                         end
      end

      # ---- bounced ----
      def bounce_category = BOUNCE_CATEGORIES[raw["bounce_category"].to_s]
      def hard_bounce? = bounced? && bounce_category == :hard
      def soft_bounce? = bounced? && bounce_category == :soft
      def bounce_code = string("code")
      def bounce_description = string("description") || string("error")

      # ---- clicked ----
      def original_url = string("url_original")
      def clicked_url = string("url_pers")

      # ---- subscription_change ----
      def suppress_sending? = raw["SuppressSending"].to_s == "true"
      def suppression_reason = string("SuppressionReason")

      # Haskimail may deliver an event more than once; use this to deduplicate.
      def idempotency_key
        [type, message_id, recipient, raw["event_time_utc"] || raw["event_time"], clicked_url || original_url].join(":")
      end

      def [](key) = raw[key.to_s]

      def to_h = raw.dup

      def inspect
        "#<#{self.class.name} type=#{type.inspect} message_id=#{message_id.inspect}>"
      end

      private

      def string(key)
        value = raw[key]
        value.nil? || value.to_s.empty? ? nil : value.to_s
      end

      def parse_time(value, offset)
        Time.strptime("#{value} #{offset}", "%Y-%m-%d %H:%M:%S %z").utc
      rescue ArgumentError
        nil
      end
    end
  end
end
