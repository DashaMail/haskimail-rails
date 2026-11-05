# frozen_string_literal: true

module Haskimail
  module Resources
    # Sender domains (account token): https://haskimail.ru/developer/api/domains-api
    class Domains < Base
      DEFAULT_PAGE_SIZE = 500

      # @return [Hash] { total_count:, domains: [{ id:, name:, dkim_verified:, spf_verified:, ... }] }
      def list(count: DEFAULT_PAGE_SIZE, offset: 0)
        api_get(path(:domains), pagination_query(count, offset))
      end

      def each(page_size: DEFAULT_PAGE_SIZE, &block)
        iterate(:domains, page_size, nil, block) { |count, offset| list(count: count, offset: offset) }
      end

      # @return [Hash] domain with :spf_text_value and :dkim_text_value DNS records
      def get(domain_id)
        api_get(path(:domains, domain_id))
      end

      def create(name)
        require_value!(:name, name)
        api_post(path(:domains), { "Name" => name.to_s.strip })
      end

      # Deletes the domain and its confirmed sender addresses. Irreversible.
      def delete(domain_id)
        api_delete(path(:domains, domain_id))
      end

      def verify_dkim(domain_id)
        api_put(path(:domains, domain_id, :verifyDkim))
      end

      def verify_spf(domain_id)
        api_put(path(:domains, domain_id, :verifyspf))
      end
    end
  end
end
