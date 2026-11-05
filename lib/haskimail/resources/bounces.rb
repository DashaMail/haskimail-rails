# frozen_string_literal: true

module Haskimail
  module Resources
    # Bounces: https://haskimail.ru/developer/api/bounce-api
    class Bounces < Base
      DEFAULT_PAGE_SIZE = 500
      # List names and their delivery-stats aliases (both are accepted by the API).
      TYPES = %w[HardBounce SoftBounce BlkBounce SpmBounce BulkBounce SpamBlock].freeze

      FILTERS = {
        type: "type", email_filter: "emailFilter", tag: "tag", message_id: "messageID",
        message_stream: "messagestream", from_date: "fromdate", to_date: "todate"
      }.freeze

      # Bounce counts by type for the last 45 days.
      # @return [Hash] { bounces: [{ name: "All", count: 253 }, { type: "HardBounce", ... }] }
      def delivery_stats
        api_get(path(:deliverystats))
      end

      # @return [Hash] { total_count:, bounces: [...] }
      def list(count: DEFAULT_PAGE_SIZE, offset: 0, **filters)
        Util.assert_known_keys!(filters.keys, FILTERS.keys, "bounce filter")
        if filters[:type] && !TYPES.include?(filters[:type].to_s)
          raise ArgumentError, "type must be one of: #{TYPES.join(', ')}"
        end

        query = pagination_query(count, offset)
        filters.each do |key, value|
          next if value.nil?

          query[FILTERS.fetch(key)] = %i[from_date to_date].include?(key) ? Util.format_date(value) : value.to_s
        end
        api_get(path(:bounces), query)
      end

      def each(page_size: DEFAULT_PAGE_SIZE, **filters, &block)
        iterate(:bounces, page_size, nil, block) { |count, offset| list(count: count, offset: offset, **filters) }
      end
    end
  end
end
