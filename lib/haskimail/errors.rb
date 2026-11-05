# frozen_string_literal: true

module Haskimail
  # Base class for every error raised by this library.
  class Error < StandardError; end

  # Missing or invalid client configuration (no token, non-HTTPS base URL, ...).
  class ConfigurationError < Error; end

  # Network-level failure: the API could not be reached or the connection broke.
  class ConnectionError < Error; end

  # The connection or the response timed out.
  class TimeoutError < ConnectionError; end

  # The API answered with something that is not valid JSON.
  class InvalidResponseError < Error
    attr_reader :status

    def initialize(message = nil, status: nil)
      super(message)
      @status = status
    end
  end

  # Numeric `ErrorCode` values documented at https://haskimail.ru/developer/api/overview.
  module ErrorCodes
    INVALID_API_TOKEN = 10
    NOT_FOUND = 12
    INTERNAL_ERROR = 100
    MISSING_REQUIRED_FIELDS = 3
    SENDING_NOT_ALLOWED = 4
    INVALID_EMAIL = 6
    ACTION_FORBIDDEN = 15
    ATTACHMENT_TOO_LARGE = 26
    ATTACHMENT_TYPE_NOT_ALLOWED = 33
    SENDING_UNAVAILABLE = 35
    TEMPORARY_SEND_ERROR = 36
    INVALID_HEADERS = 40
    SENDER_NOT_CONFIRMED = 52
    INVALID_BATCH = 300
    MODERATION_SENDER_NOT_CONFIRMED = 400
    MODERATION_RECIPIENT_NOT_CONFIRMED = 412
    MESSAGE_NOT_FOUND = 701
    TEMPLATE_SERVER_MISMATCH = 510
    DOMAIN_ALREADY_TAKEN = 512
    INBOUND_DOMAIN_WITHOUT_MX = 610
    TEMPLATE_NOT_FOUND = 1101
    TEMPLATE_VALIDATION_INPUT_INVALID = 1120
    MESSAGE_STREAM_INVALID = 1226
    INBOUND_STREAM_NOT_ARCHIVABLE = 1229
    INBOUND_STREAM_NOT_SENDABLE = 1236
  end

  # The API answered with a non-success HTTP status or a non-zero `ErrorCode`.
  class ApiError < Error
    RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze

    attr_reader :status, :error_code, :body, :headers

    def initialize(message = nil, status: nil, error_code: nil, body: nil, headers: {})
      @status = status
      @error_code = error_code
      @body = body
      @headers = headers || {}
      super(message || default_message)
    end

    # Builds the most specific error subclass for an HTTP status.
    def self.for(status:, error_code: nil, message: nil, body: nil, headers: {})
      klass = STATUS_CLASSES.fetch(status) do
        status.to_i >= 500 ? ServerError : ApiError
      end
      klass.new(message, status: status, error_code: error_code, body: body, headers: headers)
    end

    def retryable?
      RETRYABLE_STATUSES.include?(status)
    end

    # @example error.code?(Haskimail::ErrorCodes::TEMPLATE_NOT_FOUND)
    def code?(code)
      !error_code.nil? && error_code == code
    end

    private

    def default_message
      parts = []
      parts << "HTTP #{status}" if status
      parts << "ErrorCode #{error_code}" if error_code
      parts.empty? ? "Haskimail API error" : "Haskimail API error (#{parts.join(', ')})"
    end
  end

  # HTTP 401: the token is missing, wrong, or not valid for this method.
  class UnauthorizedError < ApiError; end
  # HTTP 403: the request IP is not on the account allowlist.
  class ForbiddenError < ApiError; end
  # HTTP 404: unknown method or ID.
  class NotFoundError < ApiError; end
  # HTTP 413: the batch is larger than 50 MB.
  class PayloadTooLargeError < ApiError; end
  # HTTP 422: validation error, see #error_code.
  class UnprocessableEntityError < ApiError; end
  # HTTP 429: too many requests.
  class RateLimitError < ApiError; end
  # HTTP 5xx.
  class ServerError < ApiError; end
  # HTTP 500.
  class InternalServerError < ServerError; end
  # HTTP 503: temporarily unavailable.
  class ServiceUnavailableError < ServerError; end

  class ApiError
    STATUS_CLASSES = {
      401 => UnauthorizedError,
      403 => ForbiddenError,
      404 => NotFoundError,
      413 => PayloadTooLargeError,
      422 => UnprocessableEntityError,
      429 => RateLimitError,
      500 => InternalServerError,
      503 => ServiceUnavailableError
    }.freeze
  end

  # Raised when a webhook payload fails signature or authentication checks.
  class WebhookVerificationError < Error; end
end
