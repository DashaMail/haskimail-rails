# frozen_string_literal: true

module Haskimail
  module Resources
    # Servers (account token): https://haskimail.ru/developer/api/servers-api
    class Servers < Base
      DEFAULT_PAGE_SIZE = 50
      COLORS = %w[purple blue turquoise green red orange yellow grey].freeze
      TRACK_LINKS = %w[None HtmlAndText HtmlOnly TextOnly].freeze
      DELIVERY_TYPES = %w[Live Sandbox].freeze

      UPDATABLE = %i[
        name color smtp_api_activated track_opens track_links inbound_hook_url inbound_domain
        inbound_spam_threshold raw_email_enabled
      ].freeze
      CREATABLE = (UPDATABLE + %i[delivery_type]).freeze

      def get(server_id)
        api_get(path(:servers, server_id))
      end

      # @return [Hash] { total_count:, servers: [...] }
      def list(count: DEFAULT_PAGE_SIZE, offset: 0)
        api_get(path(:servers), pagination_query(count, offset))
      end

      def each(page_size: DEFAULT_PAGE_SIZE, &block)
        iterate(:servers, page_size, nil, block) { |count, offset| list(count: count, offset: offset) }
      end

      # @example
      #   account.servers.create(name: "Интернет-магазин", color: "purple", track_links: "HtmlAndText")
      # @note the response contains server API tokens (:api_tokens) — treat it as a secret.
      def create(name:, color: "purple", **attributes)
        require_value!(:name, name)
        api_post(path(:servers), build(CREATABLE, attributes.merge(name: name, color: color)))
      end

      # Partial update: send only the attributes to change. DeliveryType cannot be changed.
      def update(server_id, **attributes)
        raise ArgumentError, "Nothing to update" if attributes.empty?

        api_put(path(:servers, server_id), build(UPDATABLE, attributes))
      end

      # Deletes the server together with its inbound rules. Irreversible.
      def delete(server_id)
        api_delete(path(:servers, server_id))
      end

      # Issues an additional server API token. The plain-text value is returned
      # only once, in this response — treat it as a secret.
      #
      # @example
      #   account.servers.issue_token(11834, name: "Интеграция 1С")
      # @return [Hash] { token:, server_id: }
      def issue_token(server_id, name: nil)
        body = name.nil? ? nil : { "Name" => name.to_s.strip }
        api_post(path(:servers, server_id, :tokens, :new), body, idempotent: false)
      end

      private

      def build(allowed, attributes)
        Util.assert_known_keys!(attributes.keys, allowed, "server attribute")
        validate!(attributes)
        Serializer.to_api(attributes.transform_keys(&:to_sym))
      end

      def validate!(attrs)
        check_enum!(attrs, :color, COLORS) { |value| value.to_s.downcase }
        check_enum!(attrs, :delivery_type, DELIVERY_TYPES)
        check_enum!(attrs, :track_links, TRACK_LINKS) unless [true, false].include?(attrs[:track_links])

        threshold = attrs[:inbound_spam_threshold]
        return if threshold.nil? || (threshold.is_a?(Integer) && threshold.between?(0, 30) && (threshold % 5).zero?)

        raise ArgumentError, "inbound_spam_threshold must be 0..30 in steps of 5"
      end

      def check_enum!(attrs, key, allowed)
        return unless attrs.key?(key)

        value = block_given? ? yield(attrs[key]) : attrs[key].to_s
        raise ArgumentError, "#{key} must be one of: #{allowed.join(', ')}" unless allowed.include?(value)
      end
    end
  end
end
