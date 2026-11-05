# frozen_string_literal: true

module Haskimail
  module Resources
    # Sending email: https://haskimail.ru/developer/api/email-api
    # and template sending: https://haskimail.ru/developer/api/templates-api
    class Emails < Base
      MAX_BATCH_SIZE = 500
      ADDRESS_FIELDS = %w[To Cc Bcc ReplyTo].freeze

      # @example
      #   client.emails.deliver(
      #     from: "Магазин <shop@example.com>", to: "ivan@example.com",
      #     subject: "Заказ №1042", html_body: "<p>Спасибо!</p>",
      #     tag: "orders", metadata: { order_id: "1042" }, message_stream: "2081"
      #   )
      # @return [Hash] { to:, submitted_at:, message_id:, error_code: 0, message: "OK" }
      def deliver(message)
        send_one("/email", build_message(message, template: false))
      end

      # @param messages [Array<Hash>] 1..500 messages; may mix plain and template messages
      # @return [Array<Hash>] one result per message, in order. Check :error_code of each item:
      #   the API returns HTTP 200 even when some messages are rejected.
      def deliver_batch(messages)
        payload = build_batch(messages) { |message| build_message(message, template: nil) }
        Serializer.from_api(connection.post("/email/batch", payload))
      end

      # @example
      #   client.emails.deliver_with_template(
      #     template_alias: "order-created", template_model: { "{{name}}" => "Иван" },
      #     from: "shop@example.com", to: "ivan@example.com"
      #   )
      def deliver_with_template(message)
        send_one("/email/withTemplate", build_message(message, template: true))
      end

      # @return [Array<Hash>] one result per message, in order (check :error_code of each)
      def deliver_batch_with_templates(messages)
        payload = build_batch(messages) { |message| build_message(message, template: true) }
        Serializer.from_api(connection.post("/email/batchWithTemplates", { "Messages" => payload }))
      end

      private

      def send_one(api_path, payload)
        Serializer.from_api(connection.post(api_path, payload))
      end

      def build_batch(messages, &)
        list = messages.respond_to?(:to_ary) ? messages.to_ary : nil
        raise ArgumentError, "messages must be an Array" unless list
        raise ArgumentError, "messages must not be empty" if list.empty?
        if list.size > MAX_BATCH_SIZE
          raise ArgumentError, "A batch may contain at most #{MAX_BATCH_SIZE} messages, got #{list.size}"
        end

        list.map(&)
      end

      # @param template [Boolean, nil] true: template required, false: body required, nil: either
      def build_message(message, template:)
        raise ArgumentError, "message must be a Hash, got #{message.class}" unless message.is_a?(Hash)

        header_keys = message.keys.select { |key| Serializer.api_key(key) == "Headers" }
        raise ArgumentError, "Duplicate field Headers (given as #{header_keys.inspect})" if header_keys.size > 1

        # Header names are literal ("X-Order-Id"), so they bypass key transformation.
        payload = Serializer.to_api(message.except(*header_keys))
        payload["Headers"] = normalize_headers(message[header_keys.first]) if header_keys.any?
        normalize!(payload)
        default_stream = connection.config.default_message_stream
        payload["MessageStream"] = default_stream.to_s if default_stream && Util.blank?(payload["MessageStream"])
        validate_message!(payload, template)
        payload.compact
      end

      def normalize!(payload)
        payload["Attachments"] = normalize_attachments(payload["Attachments"]) if payload.key?("Attachments")
        ADDRESS_FIELDS.each do |field|
          payload[field] = payload[field].join(", ") if payload[field].is_a?(Array)
        end
      end

      def validate_message!(payload, template)
        %w[From To].each do |field|
          raise ArgumentError, "#{field} is required" if Util.blank?(payload[field])
        end

        uses_template = !Util.blank?(payload["TemplateId"]) || !Util.blank?(payload["TemplateAlias"])
        if template == true && !uses_template
          raise ArgumentError, "template_id or template_alias is required"
        elsif template == false && uses_template
          raise ArgumentError, "Use deliver_with_template to send a template"
        elsif !uses_template && Util.blank?(payload["HtmlBody"]) && Util.blank?(payload["TextBody"])
          raise ArgumentError, "html_body or text_body is required"
        end
      end

      # Accepts [{name:, value:}] or a plain Hash {"X-Order-Id" => "1042"}.
      def normalize_headers(headers)
        list = if headers.is_a?(Hash)
                 headers.map do |name, value|
                   { "Name" => name.to_s, "Value" => value.to_s }
                 end
               else
                 headers
               end
        Array(list).map do |header|
          raise ArgumentError, "Each header must be a Hash with name and value" unless header.is_a?(Hash)

          header = Serializer.to_api(header)
          name = header["Name"].to_s
          value = header["Value"].to_s
          if name.match?(/[\r\n:\0]/) || name.strip.empty? || value.match?(/[\r\n\0]/)
            raise ArgumentError, "Invalid header #{name.inspect}"
          end

          { "Name" => name, "Value" => value }
        end
      end

      # Hash attachments must already carry Base64 content; use Haskimail::Attachment for raw bytes.
      def normalize_attachments(attachments)
        Array(attachments).map do |attachment|
          next attachment.to_h if attachment.is_a?(Attachment)
          raise ArgumentError, "Each attachment must be a Hash or Haskimail::Attachment" unless attachment.is_a?(Hash)

          if Util.blank?(attachment["Name"]) || Util.blank?(attachment["Content"])
            raise ArgumentError, "Each attachment needs name and content"
          end

          Attachment.assert_allowed!(attachment["Name"])
          assert_base64!(attachment)
          content_id = Attachment.normalize_content_id(attachment["ContentID"])
          content_id ? attachment.merge("ContentID" => content_id) : attachment.except("ContentID")
        end
      end

      def assert_base64!(attachment)
        Base64.strict_decode64(attachment["Content"].to_s)
      rescue ArgumentError
        raise ArgumentError, "Attachment #{attachment['Name'].inspect}: Content must be strict Base64 " \
                             "(use Haskimail::Attachment to pass raw bytes)"
      end
    end
  end
end
