# frozen_string_literal: true

module Haskimail
  # Lazily walks count/offset pages. Requests are made only while iterating.
  #
  #   client.messages.each_outbound(tag: "orders").first(1000)
  #   client.bounces.each(type: "HardBounce").each { |bounce| ... }
  class Paginator
    include Enumerable

    # @param items_key [Symbol] collection key in the (serialized) page response
    # @param page_size [Integer]
    # @param max_window [Integer, nil] API limit for count + offset
    # @yieldparam count [Integer]
    # @yieldparam offset [Integer]
    # @yieldreturn [Hash] serialized page with :total_count and items_key
    def initialize(items_key:, page_size:, max_window: nil, &fetch_page)
      raise ArgumentError, "page_size must be a positive Integer" unless page_size.is_a?(Integer) && page_size.positive?

      @items_key = items_key
      @page_size = page_size
      @max_window = max_window
      @fetch_page = fetch_page
    end

    def each(&block)
      return enum_for(:each) unless block_given?

      offset = 0
      loop do
        count = @page_size
        count = [count, @max_window - offset].min if @max_window
        break if count <= 0

        page = @fetch_page.call(count, offset)
        items = Array(page && page[@items_key])
        items.each(&block)

        offset += items.size
        total = page && page[:total_count]
        # Trust total_count when present (the server may cap the page size);
        # otherwise a short page is the last one.
        break if items.empty? || (total ? offset >= total : items.size < count)
      end
      self
    end
  end
end
