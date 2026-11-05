# frozen_string_literal: true

module Haskimail
  module Resources
    # Message streams (channels): https://haskimail.ru/developer/api/message-streams-api
    class MessageStreams < Base
      CREATABLE_TYPES = %w[Transactional Broadcasts].freeze

      # @return [Hash] { total_count:, message_streams: [...] } (archived streams included)
      def list
        api_get(path(:"message-streams"))
      end

      def get(stream_id)
        api_get(path(:"message-streams", stream_id))
      end

      # @param message_stream_type ["Transactional", "Broadcasts"] (case-insensitive)
      # @param server_id [Integer, nil] required only when called with an account token
      def create(name:, message_stream_type:, server_id: nil)
        require_value!(:name, name)
        type = CREATABLE_TYPES.find { |candidate| candidate.casecmp?(message_stream_type.to_s) }
        raise ArgumentError, "message_stream_type must be one of: #{CREATABLE_TYPES.join(', ')}" unless type

        api_post(path(:"message-streams"),
                 Util.compact("ServerID" => server_id, "Name" => name, "MessageStreamType" => type))
      end

      # Only the name can be changed.
      def update(stream_id, name:)
        require_value!(:name, name)
        api_patch(path(:"message-streams", stream_id), { "Name" => name })
      end

      # Stops sending through the stream. It is purged 45 days later unless unarchived.
      # @return [Hash] { id:, server_id:, archived_at:, expected_purge_date: }
      def archive(stream_id)
        Serializer.from_api(connection.post(path(:"message-streams", stream_id, :archive), nil, idempotent: true))
      end

      def unarchive(stream_id)
        Serializer.from_api(connection.post(path(:"message-streams", stream_id, :unarchive), nil, idempotent: true))
      end
    end
  end
end
