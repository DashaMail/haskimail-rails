# frozen_string_literal: true

module Haskimail
  module Resources
    # Suppression lists of a message stream: https://haskimail.ru/developer/api/suppressions-api
    class Suppressions < Base
      REASONS = %w[HardBounce SpamComplaint ManualSuppression].freeze

      # @return [Hash] { suppressions: [{ email_address:, suppression_reason:, origin:, created_at: }] }
      def list(stream_id)
        api_get(path(:"message-streams", stream_id, :suppressions, :dump))
      end
      alias dump list

      # Stops sending to the addresses through this stream.
      # @return [Hash] { suppressions: [{ email_address:, status: "Suppressed"|"Failed", message: }] }
      def create(stream_id, email_addresses)
        api_post(path(:"message-streams", stream_id, :suppressions), body(email_addresses), idempotent: true)
      end
      alias suppress create

      # Only manual and hard-bounce suppressions can be removed.
      # @return [Hash] { suppressions: [{ email_address:, status: "Deleted"|"Failed", message: }] }
      def delete(stream_id, email_addresses)
        api_post(path(:"message-streams", stream_id, :suppressions, :delete), body(email_addresses), idempotent: true)
      end
      alias unsuppress delete

      private

      def body(email_addresses)
        list = Array(email_addresses).map { |email| email.to_s.strip }.reject(&:empty?).uniq
        raise ArgumentError, "At least one email address is required" if list.empty?

        { "Suppressions" => list.map { |email| { "EmailAddress" => email } } }
      end
    end
  end
end
