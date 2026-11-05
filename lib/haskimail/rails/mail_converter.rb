# frozen_string_literal: true

require "base64"
require "json"

module Haskimail
  module Rails
    # Converts a Mail::Message (as built by ActionMailer) into an API payload.
    module MailConverter
      # Headers mapped to dedicated API fields or managed by Haskimail itself.
      # Message-ID is reserved too: ActionMailer generates one for every message
      # and Haskimail assigns its own MessageID.
      RESERVED_HEADERS = %w[
        from to cc bcc reply-to subject date sender return-path received mime-version message-id
        content-type content-transfer-encoding content-disposition content-id
      ].freeze

      # User data that is sent even when empty.
      KEEP_WHEN_EMPTY = %w[TemplateModel].freeze

      # SMTP-compatible headers (https://haskimail.ru/developer/user-guide/send-email-with-smtp),
      # honoured here too so mailers work the same over SMTP and the HTTP API.
      HM_TAG = "x-hm-tag"
      HM_METADATA = "x-hm-metadata"
      HM_TRACK_OPENS = "x-hm-trackopens"
      HM_NO_TRACK_OPENS = "x-hm-no-track-opens"
      HM_NO_TRACK_CLICK = "x-hm-no-track-click"
      # Converted into API fields; other X-HM-* headers (X-HM-Domain,
      # X-HM-MessageID) are passed through to Haskimail unchanged.
      CONSUMED_HM_HEADERS = [HM_TAG, HM_METADATA, HM_TRACK_OPENS, HM_NO_TRACK_OPENS, HM_NO_TRACK_CLICK].freeze

      module_function

      # @param mail [Mail::Message]
      # @return [Hash] API payload with String keys
      def call(mail)
        options = mail.respond_to?(:haskimail) ? mail.haskimail : MessageOptions.new
        payload = {
          "From" => address_list(mail, :from).first,
          "To" => join(address_list(mail, :to)),
          "Cc" => join(address_list(mail, :cc)),
          "Bcc" => join(address_list(mail, :bcc)),
          "ReplyTo" => join(address_list(mail, :reply_to)),
          "Subject" => mail.subject,
          "Headers" => custom_headers(mail),
          "Attachments" => attachments(mail)
        }
        payload.merge!(bodies(mail)) unless options.template?
        payload.merge!(header_options(mail))
        payload.merge!(options.to_api)
        payload.reject { |key, value| Util.blank?(value) && value != false && !KEEP_WHEN_EMPTY.include?(key) }
      end

      def address_list(mail, field)
        header = mail[field]
        return [] unless header

        Array(header.respond_to?(:formatted) ? header.formatted : header.value).compact
      end

      def join(list)
        list.empty? ? nil : list.join(", ")
      end

      def bodies(mail)
        if mail.multipart?
          { "HtmlBody" => decode(mail.html_part), "TextBody" => decode(mail.text_part) }
        elsif mail.mime_type == "text/html"
          { "HtmlBody" => decode(mail) }
        else
          { "TextBody" => decode(mail) }
        end
      end

      def decode(part)
        return nil unless part

        part.decoded.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      end

      def custom_headers(mail)
        mail.header.fields.filter_map do |field|
          name = field.name.to_s
          key = name.downcase
          next if RESERVED_HEADERS.include?(key) || CONSUMED_HM_HEADERS.include?(key)

          { "Name" => name, "Value" => field.value.to_s }
        end
      end

      def attachments(mail)
        mail.attachments.map do |attachment|
          Haskimail::Attachment.assert_allowed!(attachment.filename)
          item = {
            "Name" => attachment.filename,
            "Content" => Base64.strict_encode64(attachment.decoded),
            "ContentType" => attachment.mime_type
          }
          # Bare Content-ID: the HTML references it as "cid:<id>" (Rails' attachment.url).
          item["ContentID"] = Haskimail::Attachment.normalize_content_id(attachment.content_id) if attachment.inline?
          item
        end
      end

      # Values from X-HM-* headers; explicit `message.haskimail` settings win.
      def header_options(mail)
        result = {}
        result["Tag"] = header_value(mail, HM_TAG)
        if (raw = header_value(mail, HM_METADATA))
          metadata = JSON.parse(raw)
          raise ArgumentError, "X-HM-Metadata must be a JSON object" unless metadata.is_a?(Hash)

          result["Metadata"] = metadata
        end
        track_opens = header_value(mail, HM_TRACK_OPENS)
        result["TrackOpens"] = track_opens.casecmp?("true") if track_opens
        result["TrackOpens"] = false if header_value(mail, HM_NO_TRACK_OPENS)
        result["TrackLinks"] = false if header_value(mail, HM_NO_TRACK_CLICK)
        result.compact
      rescue JSON::ParserError
        raise ArgumentError, "X-HM-Metadata must be valid JSON"
      end

      def header_value(mail, name)
        field = mail.header.fields.find { |candidate| candidate.name.to_s.casecmp?(name) }
        field&.value&.to_s
      end
    end
  end
end
