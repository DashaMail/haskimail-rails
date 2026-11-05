# frozen_string_literal: true

require "base64"

module Haskimail
  module Webhooks
    # An inbound email posted to the server's InboundHookUrl
    # (https://haskimail.ru/developer/webhooks/inbound-webhook).
    class InboundMessage
      Address = Struct.new(:email, :name, :mailbox_hash, keyword_init: true)

      # Inbound attachment; content is decoded lazily.
      class Attachment
        attr_reader :name, :content_type, :content_length, :content_id

        def initialize(data)
          @name = data["Name"].to_s
          @content_type = data["ContentType"]
          @content_length = data["ContentLength"]
          @content_id = data["ContentID"].to_s
          @encoded = data["Content"].to_s
        end

        def inline? = !content_id.empty?

        # @return [String] raw bytes (binary)
        def read
          Base64.decode64(@encoded)
        end

        def inspect
          "#<#{self.class.name} name=#{name.inspect} content_type=#{content_type.inspect}>"
        end
      end

      attr_reader :raw

      def initialize(data)
        @raw = data.transform_keys(&:to_s).freeze
      end

      def type = :inbound
      def message_id = raw["MessageID"]
      def message_stream = raw["MessageStream"]&.to_s
      def subject = raw["Subject"]
      def date = raw["Date"]
      def tag = raw["Tag"]
      def mailbox_hash = raw["MailboxHash"]
      def original_recipient = raw["OriginalRecipient"]
      def reply_to = raw["ReplyTo"]
      def text_body = raw["TextBody"]
      def html_body = raw["HtmlBody"]
      def stripped_text_reply = raw["StrippedTextReply"]
      def raw_email = raw["RawEmail"]

      def from
        full = raw["FromFull"]
        full.is_a?(Hash) ? address(full) : Address.new(email: raw["From"], name: raw["FromName"], mailbox_hash: nil)
      end

      def to = addresses("ToFull")
      def cc = addresses("CcFull")
      def bcc = addresses("BccFull")

      # @return [Array<Hash>] [{ "Name" => ..., "Value" => ... }]
      def headers = Array(raw["Headers"])

      # Case-insensitive lookup of the first header with this name.
      def header(name)
        headers.find { |header| header["Name"].to_s.casecmp?(name.to_s) }&.fetch("Value", nil)
      end

      def spam_score
        value = header("X-Spam-Score")
        value && Float(value, exception: false)
      end

      def attachments
        @attachments ||= Array(raw["Attachments"]).map { |data| Attachment.new(data) }
      end

      def [](key) = raw[key.to_s]
      def to_h = raw.dup

      def inspect
        "#<#{self.class.name} message_id=#{message_id.inspect} attachments=#{attachments.size}>"
      end

      private

      def addresses(key)
        Array(raw[key]).map { |data| address(data) }
      end

      def address(data)
        Address.new(email: data["Email"], name: data["Name"], mailbox_hash: data["MailboxHash"])
      end
    end
  end
end
