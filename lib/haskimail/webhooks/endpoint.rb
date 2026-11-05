# frozen_string_literal: true

require "json"

module Haskimail
  module Webhooks
    # A Rack app that receives Haskimail webhooks, authenticates them and hands
    # parsed events to your code. Mount it in config/routes.rb:
    #
    #   mount Haskimail::Webhooks::Endpoint.new(
    #     signature_key: Rails.application.credentials.dig(:haskimail, :webhook_key),
    #     username: "haskimail", password: Rails.application.credentials.dig(:haskimail, :webhook_password)
    #   ) { |event| HaskimailWebhookJob.perform_later(event.to_h) }, at: "/haskimail/webhooks"
    #
    # Configure the webhook URL in Haskimail as https://haskimail:PASSWORD@your.app/haskimail/webhooks.
    #
    # Every payload is also published via ActiveSupport::Notifications as
    # "webhook.haskimail" with payload { type:, event: }.
    #
    # Security:
    # * Basic auth is required (it is checked before the body is read).
    # * signature_key adds a per-event check. Haskimail signs only recipient and
    #   message_id, so a captured signature can be replayed with another event
    #   type; that is why signature-only mode needs allow_signature_only: true.
    # * Inbound emails are not signed, so they are accepted only with Basic auth.
    #
    # Responses: 200 handled; 401 bad credentials; 403 bad or missing signature;
    # 500 when your handler raises. Haskimail retries 5xx for every webhook; for
    # inbound emails it also retries other non-2xx responses except 403.
    class Endpoint
      DEFAULT_MAX_BODY_BYTES = 32 * 1024 * 1024 # inbound email up to 10 MB, Base64-encoded
      JSON_HEADERS = { "content-type" => "application/json" }.freeze

      # @param signature_key [String, nil] account webhook key; when set, events without a
      #   valid `secret` are rejected
      # @param username [String, nil] Basic auth user; when set, Basic auth is required
      # @param password [String, nil] Basic auth password
      # @param logger [#error, nil]
      # @param allow_signature_only [Boolean] accept events authenticated only by signature_key
      #   (inbound emails are then rejected)
      # @param allow_unauthenticated [Boolean] explicitly accept requests without any
      #   authentication (only for local development)
      def initialize(signature_key: nil, username: nil, password: nil, max_body_bytes: DEFAULT_MAX_BODY_BYTES,
                     logger: nil, allow_signature_only: false, allow_unauthenticated: false, &handler)
        @signature_key = signature_key.to_s.empty? ? nil : Secret.new(signature_key)
        @username = username.to_s.empty? ? nil : Secret.new(username)
        @password = password.to_s.empty? ? nil : Secret.new(password)
        @max_body_bytes = max_body_bytes
        @logger = logger
        @allow_signature_only = allow_signature_only
        @allow_unauthenticated = allow_unauthenticated
        @handler = handler
        validate_settings!
      end

      def call(env)
        return respond(405, "Method Not Allowed", "allow" => "POST") unless env["REQUEST_METHOD"] == "POST"
        return unauthorized unless authenticated?(env)

        body = read_body(env)
        return respond(413, "Payload Too Large") unless body

        payload = Webhooks.parse(body)
        return respond(403, "Forbidden") unless trusted?(payload)

        dispatch(payload)
        respond(200, "OK")
      rescue ParseError
        respond(400, "Bad Request")
      rescue StandardError => e
        @logger&.error("[Haskimail] webhook handler failed: #{e.class}: #{e.message}")
        respond(500, "Internal Server Error")
      end

      def inspect
        "#<#{self.class.name} signed=#{!@signature_key.nil?} basic_auth=#{basic_auth?}>"
      end

      private

      def validate_settings!
        if @username.nil? != @password.nil?
          raise ConfigurationError, "Set both username and password for webhook Basic auth"
        end
        unless @max_body_bytes.is_a?(Integer) && @max_body_bytes.positive?
          raise ConfigurationError, "max_body_bytes must be a positive Integer"
        end
        return if basic_auth? || @allow_unauthenticated
        return if @signature_key && @allow_signature_only

        raise ConfigurationError, "Configure Basic auth (username/password) for the webhook endpoint. " \
                                  "Signature-only mode needs allow_signature_only: true; " \
                                  "allow_unauthenticated: true is for local development only"
      end

      def basic_auth?
        !@username.nil?
      end

      def authenticated?(env)
        return true unless basic_auth?

        Webhooks.valid_basic_auth?(env["HTTP_AUTHORIZATION"], username: @username.reveal, password: @password.reveal)
      end

      # Events must carry a valid signature when a key is configured. Inbound
      # emails are unsigned, so they require Basic auth.
      # A configured signature key is always enforced, even with allow_unauthenticated.
      def trusted?(payload)
        if payload.is_a?(Event)
          @signature_key.nil? || Webhooks.valid_signature?(payload, key: @signature_key.reveal)
        else
          basic_auth? || @allow_unauthenticated
        end
      end

      def read_body(env)
        input = env["rack.input"]
        return "" unless input

        input.rewind if input.respond_to?(:rewind)
        body = String.new(input.read(@max_body_bytes + 1).to_s)
        input.rewind if input.respond_to?(:rewind)
        body.bytesize > @max_body_bytes ? nil : body.force_encoding(Encoding::UTF_8)
      end

      def dispatch(payload)
        if defined?(ActiveSupport::Notifications)
          ActiveSupport::Notifications.instrument("webhook.haskimail", type: payload.type, event: payload) do
            @handler&.call(payload)
          end
        else
          @handler&.call(payload)
        end
      end

      def unauthorized
        respond(401, "Unauthorized", "www-authenticate" => 'Basic realm="Haskimail webhooks"')
      end

      def respond(status, message, extra_headers = {})
        [status, JSON_HEADERS.merge(extra_headers), [JSON.generate(status: message)]]
      end
    end
  end
end
