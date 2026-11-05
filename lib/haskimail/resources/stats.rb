# frozen_string_literal: true

module Haskimail
  module Resources
    # Sending statistics: https://haskimail.ru/developer/api/stats-api
    #
    # Every method accepts from_date:, to_date: (Date, Time or "YYYY-MM-DD")
    # and message_stream:.
    class Stats < Base
      FILTERS = { from_date: "fromdate", to_date: "todate", message_stream: "messagestream" }.freeze

      # @return [Hash] { sent:, bounced:, opened:, clicked:, unsubscribed:, spam_complaints:,
      #   bounce_rate:, spam_complaints_rate:, open_rate:, click_rate: }
      def overview(**filters)
        fetch(path(:stats), filters)
      end

      # @return [Hash] { days: [{ date:, sent: }] }
      def sends(**filters)
        fetch(path(:stats, :sends), filters)
      end

      # @return [Hash] { days: [{ date:, hard_bounce:, soft_bounce: }] }
      def bounces(**filters)
        fetch(path(:stats, :bounces), filters)
      end

      # @return [Hash] { days: [{ date:, spam_complaint: }] }
      def spam_complaints(**filters)
        fetch(path(:stats, :spam), filters)
      end

      # @return [Hash] { days: [{ date:, opens: }] }
      def opens(**filters)
        fetch(path(:stats, :opens), filters)
      end

      # @return [Hash] { days: [{ date:, clicks: }] }
      def clicks(**filters)
        fetch(path(:stats, :clicks), filters)
      end

      # @return [Hash] { days: [{ date:, desktop:, mobile:, web_mail:, unknown: }], desktop:, ... }
      def open_platforms(**filters)
        fetch(path(:stats, :opens, :platforms), filters)
      end

      # @return [Hash] { days: [{ date:, platforms... }], desktop:, mobile:, web_mail:, unknown: }
      def click_platforms(**filters)
        fetch(path(:stats, :clicks, :platforms), filters)
      end

      # Client names are data, so they are kept verbatim:
      # @return [Hash] { days: [{ date: "2026-10-01", counts: { "Apple Mail" => 17 } }],
      #   totals: { "Apple Mail" => 32 } }
      def email_clients(**filters)
        breakdown(path(:stats, :opens, :emailclients), filters)
      end

      # @return [Hash] { days: [{ date:, counts: { "Chrome" => 9 } }], totals: { "Chrome" => 23 } }
      def browser_families(**filters)
        breakdown(path(:stats, :clicks, :browserfamilies), filters)
      end

      private

      def fetch(api_path, filters)
        api_get(api_path, query(filters))
      end

      def breakdown(api_path, filters)
        raw = connection.get(api_path, query: query(filters)) || {}
        days = Array(raw["Days"]).map do |day|
          { date: day["Date"], counts: day.except("Date") }
        end
        { days: days, totals: raw.except("Days") }
      end

      def query(filters)
        Util.assert_known_keys!(filters.keys, FILTERS.keys, "stats filter")
        filters.each_with_object({}) do |(key, value), query|
          next if value.nil?

          query[FILTERS.fetch(key)] = key == :message_stream ? value.to_s : Util.format_date(value)
        end
      end
    end
  end
end
