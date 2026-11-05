# frozen_string_literal: true

module Haskimail
  module Resources
    # Sent and received messages, opens and clicks:
    # https://haskimail.ru/developer/api/messages-api
    class Messages < Base
      DEFAULT_PAGE_SIZE = 100
      MAX_PAGE_SIZE = 500
      MAX_WINDOW = 10_000 # count + offset limit for outbound, opens and clicks
      INBOUND_STATUSES = %w[queued processed blocked failed scheduled].freeze

      OUTBOUND_FILTERS = {
        recipient: "recipient", from_email: "fromemail", tag: "tag", subject: "subject",
        message_stream: "messagestream", from_date: "fromdate", to_date: "todate"
      }.freeze
      EVENT_FILTERS = {
        recipient: "recipient", tag: "tag", message_stream: "messagestream",
        from_date: "fromdate", to_date: "todate"
      }.freeze
      MESSAGE_EVENT_FILTERS = EVENT_FILTERS.except(:from_date, :to_date).freeze
      INBOUND_FILTERS = {
        recipient: "recipient", from_email: "fromemail", subject: "subject", mailbox_hash: "mailboxhash",
        status: "status", from_date: "fromdate", to_date: "todate"
      }.freeze

      # ---- Outbound -------------------------------------------------------

      # @return [Hash] { total_count:, messages: [...] } — one record per recipient
      def outbound(count: DEFAULT_PAGE_SIZE, offset: 0, **filters)
        api_get(path(:messages), windowed_query(count, offset, filters, OUTBOUND_FILTERS))
      end

      def each_outbound(page_size: DEFAULT_PAGE_SIZE, **filters, &block)
        iterate(:messages, page_size, MAX_WINDOW, block, max_page_size: MAX_PAGE_SIZE) do |count, offset|
          outbound(count: count, offset: offset, **filters)
        end
      end

      def outbound_details(message_id)
        api_get(path(:messages, message_id, :details))
      end

      # ---- Opens ------------------------------------------------------------

      # @return [Hash] { total_count:, opens: [...] }
      def opens(count: DEFAULT_PAGE_SIZE, offset: 0, **filters)
        api_get(path(:messages, :opens), windowed_query(count, offset, filters, EVENT_FILTERS))
      end

      def each_open(page_size: DEFAULT_PAGE_SIZE, **filters, &block)
        iterate(:opens, page_size, MAX_WINDOW, block, max_page_size: MAX_PAGE_SIZE) do |count, offset|
          opens(count: count, offset: offset, **filters)
        end
      end

      def opens_for(message_id, count: DEFAULT_PAGE_SIZE, offset: 0, **filters)
        api_get(path(:messages, :opens, message_id),
                windowed_query(count, offset, filters, MESSAGE_EVENT_FILTERS))
      end

      # ---- Clicks -----------------------------------------------------------

      # @return [Hash] { total_count:, clicks: [...] }
      def clicks(count: DEFAULT_PAGE_SIZE, offset: 0, **filters)
        api_get(path(:messages, :clicks), windowed_query(count, offset, filters, EVENT_FILTERS))
      end

      def each_click(page_size: DEFAULT_PAGE_SIZE, **filters, &block)
        iterate(:clicks, page_size, MAX_WINDOW, block, max_page_size: MAX_PAGE_SIZE) do |count, offset|
          clicks(count: count, offset: offset, **filters)
        end
      end

      def clicks_for(message_id, count: DEFAULT_PAGE_SIZE, offset: 0, **filters)
        api_get(path(:messages, :clicks, message_id),
                windowed_query(count, offset, filters, MESSAGE_EVENT_FILTERS))
      end

      # ---- Inbound ----------------------------------------------------------

      # @return [Hash] { total_count:, inbound_messages: [...] } (last 45 days)
      def inbound(count: DEFAULT_PAGE_SIZE, offset: 0, **filters)
        Util.assert_known_keys!(filters.keys, INBOUND_FILTERS.keys, "inbound filter")
        if filters[:status] && !INBOUND_STATUSES.include?(filters[:status].to_s.downcase)
          raise ArgumentError, "status must be one of: #{INBOUND_STATUSES.join(', ')}"
        end

        query = pagination_query(count, offset, max_count: MAX_PAGE_SIZE)
        filters.each do |key, value|
          query[INBOUND_FILTERS.fetch(key)] = format_filter(key, value, separator: "T")
        end
        query["status"] = query["status"].downcase if query["status"]
        api_get(path(:messages, :inbound), query)
      end

      def each_inbound(page_size: DEFAULT_PAGE_SIZE, **filters, &block)
        iterate(:inbound_messages, page_size, nil, block, max_page_size: MAX_PAGE_SIZE) do |count, offset|
          inbound(count: count, offset: offset, **filters)
        end
      end

      def inbound_details(message_id)
        api_get(path(:messages, :inbound, message_id, :details))
      end

      # Delivers a Blocked inbound message to the webhook, skipping block rules and the spam filter.
      # Never retried automatically: a repeat could post the message to your webhook twice.
      def bypass_inbound(message_id)
        api_put(path(:messages, :inbound, message_id, :bypass), idempotent: false)
      end

      # Re-sends a Failed inbound message to the webhook.
      def retry_inbound(message_id)
        api_put(path(:messages, :inbound, message_id, :retry), idempotent: false)
      end

      private

      def windowed_query(count, offset, filters, allowed)
        Util.assert_known_keys!(filters.keys, allowed.keys, "filter")
        query = pagination_query(count, offset, max_count: MAX_PAGE_SIZE, max_window: MAX_WINDOW)
        filters.each { |key, value| query[allowed.fetch(key)] = format_filter(key, value) }
        query
      end

      def format_filter(key, value, separator: " ")
        return nil if value.nil?
        return Util.format_datetime(value, separator: separator) if %i[from_date to_date].include?(key)

        value.to_s
      end
    end
  end
end
