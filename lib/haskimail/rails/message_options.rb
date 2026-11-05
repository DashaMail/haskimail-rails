# frozen_string_literal: true

module Haskimail
  module Rails
    # Haskimail-specific settings attached to a Mail::Message (`message.haskimail`).
    class MessageOptions
      ATTRIBUTES = %i[tag metadata message_stream track_opens track_links template template_model].freeze

      attr_reader(*ATTRIBUTES)
      # Response of the last successful delivery ({ message_id:, submitted_at:, ... }).
      attr_accessor :response

      def assign(options)
        Util.assert_known_keys!(options.keys, ATTRIBUTES, "haskimail")
        options.each { |key, value| public_send(:"#{key}=", value) }
        self
      end

      def tag=(value)
        @tag = value&.to_s
      end

      def metadata=(value)
        raise ArgumentError, "metadata must be a Hash" unless value.nil? || value.is_a?(Hash)

        @metadata = value
      end

      def message_stream=(value)
        @message_stream = value&.to_s
      end

      def track_opens=(value)
        raise ArgumentError, "track_opens must be true, false or nil" unless [true, false, nil].include?(value)

        @track_opens = value
      end

      def track_links=(value)
        raise ArgumentError, "track_links must be true, false or nil" unless [true, false, nil].include?(value)

        @track_links = value
      end

      # @param value [Integer, String] template ID (Integer) or alias/name (String)
      def template=(value)
        unless value.nil? || value.is_a?(Integer) || (value.is_a?(String) && !value.strip.empty?)
          raise ArgumentError, "template must be an Integer ID or a String alias"
        end

        @template = value
      end

      def template_model=(value)
        raise ArgumentError, "template_model must be a Hash" unless value.nil? || value.is_a?(Hash)

        @template_model = value
      end

      def template?
        !template.nil?
      end

      def message_id
        response && response[:message_id]
      end

      def to_api
        payload = {
          "Tag" => tag, "Metadata" => metadata, "MessageStream" => message_stream,
          "TrackOpens" => track_opens, "TrackLinks" => track_links
        }
        if template?
          payload[template.is_a?(Integer) ? "TemplateId" : "TemplateAlias"] = template
          payload["TemplateModel"] = template_model || {}
        end
        payload.compact
      end
    end

    # Adds `message.haskimail` to Mail::Message.
    module MailExtension
      def haskimail
        @haskimail ||= MessageOptions.new
      end
    end
  end
end
