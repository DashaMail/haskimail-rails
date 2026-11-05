# frozen_string_literal: true

require "json"
require "openssl"
require "digest"

require_relative "webhooks/event"
require_relative "webhooks/inbound_message"
require_relative "webhooks/endpoint"

module Haskimail
  # Parsing and verification of incoming webhook requests
  # (https://haskimail.ru/developer/webhooks/webhooks-overview).
  #
  #   event = Haskimail::Webhooks.parse(request.raw_post)
  #   Haskimail::Webhooks.verify_signature!(event, key: ENV["HASKIMAIL_WEBHOOK_KEY"])
  #   case event
  #   when Haskimail::Webhooks::Event          then event.bounced? ...
  #   when Haskimail::Webhooks::InboundMessage then event.stripped_text_reply ...
  #   end
  module Webhooks
    class ParseError < Error; end

    module_function

    # @param payload [String, Hash] raw JSON body or an already parsed Hash
    # @return [Event, InboundMessage]
    def parse(payload)
      data = payload.is_a?(String) ? JSON.parse(payload) : payload
      raise ParseError, "Webhook payload must be a JSON object" unless data.is_a?(Hash)

      data = data.transform_keys(&:to_s)
      return Event.new(data) if data.key?("event")
      return InboundMessage.new(data) if data.key?("MessageID") || data.key?("FromFull")

      raise ParseError, "Unrecognized Haskimail webhook payload"
    rescue JSON::ParserError => e
      raise ParseError, "Invalid JSON in webhook payload: #{e.message}"
    end

    # MD5(recipient + message_id + key), as documented by Haskimail. Compared in
    # constant time. Inbound webhooks are not signed — protect them with Basic auth.
    #
    # Note: the upstream scheme signs only recipient and message_id, so a captured
    # secret can be replayed with another event type. Use Basic auth as well.
    def valid_signature?(event, key:)
      event = parse(event) unless event.is_a?(Event) || event.is_a?(InboundMessage)
      return false unless event.is_a?(Event)

      secret = event.secret.to_s.downcase
      return false if key.to_s.empty? || secret.empty?

      expected = Digest::MD5.hexdigest("#{event.recipient}#{event.message_id}#{key}")
      secure_compare(expected, secret)
    end

    # @return [Event] the parsed, verified event
    # @raise [WebhookVerificationError]
    def verify_signature!(event, key:)
      event = parse(event) unless event.is_a?(Event) || event.is_a?(InboundMessage)
      raise WebhookVerificationError, "Invalid Haskimail webhook signature" unless valid_signature?(event, key: key)

      event
    end

    # Checks an "Authorization: Basic ..." header against expected credentials.
    def valid_basic_auth?(authorization, username:, password:)
      scheme, encoded = authorization.to_s.split(" ", 2)
      return false unless scheme&.casecmp?("basic") && encoded

      given_user, given_password = encoded.unpack1("m").split(":", 2)
      # Evaluate both comparisons so timing does not reveal which part was wrong.
      user_ok = secure_compare(Digest::SHA256.hexdigest(given_user.to_s), Digest::SHA256.hexdigest(username.to_s))
      password_ok = secure_compare(Digest::SHA256.hexdigest(given_password.to_s),
                                   Digest::SHA256.hexdigest(password.to_s))
      user_ok & password_ok
    end

    def secure_compare(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize

      OpenSSL.fixed_length_secure_compare(left, right)
    end
  end
end
