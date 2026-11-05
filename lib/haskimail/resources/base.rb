# frozen_string_literal: true

module Haskimail
  module Resources
    # Common plumbing for API resources: path building, serialization, validation.
    class Base
      def initialize(connection)
        @connection = connection
      end

      def inspect
        "#<#{self.class.name}>"
      end

      private

      attr_reader :connection

      def path(*segments)
        segments.map do |segment|
          segment.is_a?(Symbol) ? segment.to_s : Util.escape_path_segment(segment)
        end.unshift("").join("/")
      end

      def api_get(api_path, query = nil)
        Serializer.from_api(connection.get(api_path, query: query))
      end

      def api_post(api_path, body = nil, idempotent: false)
        Serializer.from_api(connection.post(api_path, body && Serializer.to_api(body), idempotent: idempotent))
      end

      def api_put(api_path, body = nil, idempotent: true)
        Serializer.from_api(connection.put(api_path, body && Serializer.to_api(body), idempotent: idempotent))
      end

      def api_patch(api_path, body = nil)
        Serializer.from_api(connection.patch(api_path, body && Serializer.to_api(body)))
      end

      def api_delete(api_path)
        Serializer.from_api(connection.delete(api_path))
      end

      # Returns an Enumerator, or iterates right away when a block is given.
      def iterate(items_key, page_size, max_window, consumer, max_page_size: nil, &)
        Util.assert_range!(:page_size, page_size, 1..(max_page_size || Float::INFINITY))
        paginator = Paginator.new(items_key: items_key, page_size: page_size, max_window: max_window, &)
        consumer ? paginator.each(&consumer) : paginator.each
      end

      def pagination_query(count, offset, max_count: nil, max_window: nil)
        Util.assert_range!(:count, count, 1..(max_count || Float::INFINITY))
        Util.assert_range!(:offset, offset, 0..Float::INFINITY)
        if max_window && count + offset > max_window
          raise ArgumentError, "count + offset must not exceed #{max_window} (API limit)"
        end

        { "count" => count, "offset" => offset }
      end

      def require_value!(name, value)
        raise ArgumentError, "#{name} is required" if Util.blank?(value)

        value
      end

      def require_boolean!(name, value)
        raise ArgumentError, "#{name} must be true or false" unless [true, false].include?(value)

        value
      end
    end
  end
end
