# frozen_string_literal: true

module Haskimail
  module Resources
    # Inbound block rules: https://haskimail.ru/developer/api/inbound-rules-triggers-api
    class InboundRules < Base
      DEFAULT_PAGE_SIZE = 100
      MAX_PAGE_SIZE = 500

      # @return [Hash] { total_count:, inbound_rules: [{ id:, rule: }] }
      def list(count: DEFAULT_PAGE_SIZE, offset: 0)
        api_get(path(:triggers, :inboundrules), pagination_query(count, offset, max_count: MAX_PAGE_SIZE))
      end

      def each(page_size: DEFAULT_PAGE_SIZE, &block)
        iterate(:inbound_rules, page_size, nil, block, max_page_size: MAX_PAGE_SIZE) do |count, offset|
          list(count: count, offset: offset)
        end
      end

      # @param rule [String] an email address ("spam@example.com") or a domain ("example.org")
      # @return [Hash] { id:, rule: }
      def create(rule)
        require_value!(:rule, rule)
        api_post(path(:triggers, :inboundrules), { "Rule" => rule.to_s.strip })
      end

      def delete(rule_id)
        api_delete(path(:triggers, :inboundrules, rule_id))
      end
    end
  end
end
