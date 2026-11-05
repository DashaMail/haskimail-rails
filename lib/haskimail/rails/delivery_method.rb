# frozen_string_literal: true

module Haskimail
  module Rails
    # ActionMailer delivery method.
    #
    #   # config/environments/production.rb
    #   config.action_mailer.delivery_method = :haskimail
    #   config.action_mailer.haskimail_settings = {
    #     api_token: Rails.application.credentials.dig(:haskimail, :server_token)
    #   }
    #
    # Settings: :api_token (or :server_token), :return_response, and any
    # Haskimail::Configuration option (:default_message_stream, :read_timeout, ...).
    # Without a token the global Haskimail configuration is used.
    class DeliveryMethod
      TOKEN_KEYS = %i[api_token server_token].freeze

      attr_accessor :settings

      def initialize(settings = {})
        @settings = (settings || {}).to_h.transform_keys(&:to_sym)
      end

      # @return [Mail::Message, Hash] the message, or the API response with return_response: true
      def deliver!(mail)
        payload = MailConverter.call(mail)
        client = build_client
        response = mail.haskimail.template? ? client.deliver_with_template(payload) : client.deliver(payload)
        mail.haskimail.response = response
        settings[:return_response] ? response : mail
      end

      def inspect
        "#<#{self.class.name} settings=#{settings.except(*TOKEN_KEYS).inspect}>"
      end

      # Safe for logs and error trackers: tokens are redacted.
      def as_json(*)
        { "settings" => settings.to_h { |k, v| [k.to_s, TOKEN_KEYS.include?(k) ? Secret::REDACTED : v] } }
      end

      def to_json(*args)
        as_json.to_json(*args)
      end

      private

      def build_client
        token = settings[:api_token] || settings[:server_token]
        options = settings.except(*TOKEN_KEYS, :return_response)
        ServerClient.new(token, **options)
      end
    end
  end
end
