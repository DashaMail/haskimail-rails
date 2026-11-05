# frozen_string_literal: true

require "uri"

module Haskimail
  module Resources
    # Webhook management: https://haskimail.ru/developer/api/webhooks-api
    # (for parsing incoming webhook requests see Haskimail::Webhooks)
    class Webhooks < Base
      TRIGGERS = %i[delivery bounce spam_complaint open click subscription_change].freeze

      # @return [Hash] { webhooks: [{ id:, url:, message_stream:, triggers: {...} }] }
      def list
        api_get(path(:webhooks))
      end

      def get(webhook_id)
        api_get(path(:webhooks, webhook_id))
      end

      # @param triggers [Hash] e.g. { delivery: true, bounce: true } or
      #   { delivery: { enabled: true } }. Events not listed are disabled.
      # @example
      #   client.webhooks.create(url: "https://example.com/haskimail/events",
      #                          message_stream: "2081", triggers: { delivery: true, bounce: true })
      def create(url:, triggers:, message_stream: nil)
        api_post(path(:webhooks), Util.compact(
                                    "Url" => validate_url!(url),
                                    "MessageStream" => message_stream&.to_s,
                                    "Triggers" => build_triggers(triggers)
                                  ))
      end

      # Only the given attributes and events change; the stream cannot be changed.
      def update(webhook_id, url: nil, triggers: nil)
        body = {}
        body["Url"] = validate_url!(url) unless url.nil?
        body["Triggers"] = build_triggers(triggers) unless triggers.nil?
        raise ArgumentError, "Nothing to update: pass url: and/or triggers:" if body.empty?

        api_put(path(:webhooks, webhook_id), body)
      end

      def delete(webhook_id)
        api_delete(path(:webhooks, webhook_id))
      end

      private

      def validate_url!(url)
        uri = URI.parse(url.to_s)
        unless uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty?
          raise ArgumentError, "url must be an absolute http(s) URL"
        end

        url.to_s
      rescue URI::InvalidURIError
        raise ArgumentError, "url must be an absolute http(s) URL"
      end

      def build_triggers(triggers)
        raise ArgumentError, "triggers must be a Hash" unless triggers.is_a?(Hash)
        raise ArgumentError, "triggers must list at least one event: #{TRIGGERS.join(', ')}" if triggers.empty?

        Util.assert_known_keys!(triggers.keys, TRIGGERS, "trigger")
        triggers.to_h do |event, setting|
          enabled = if setting.is_a?(Hash)
                      setting.fetch(:enabled) do
                        setting.fetch("Enabled", setting["enabled"])
                      end
                    else
                      setting
                    end
          require_boolean!("triggers[:#{event}]", enabled)
          [Serializer.api_key(event.to_sym), { "Enabled" => enabled }]
        end
      end
    end
  end
end
