# frozen_string_literal: true

module Haskimail
  module Resources
    # Templates stored on a server: https://haskimail.ru/developer/api/templates-api
    class Templates < Base
      DEFAULT_PAGE_SIZE = 500

      # @param id_or_alias [Integer, String] template ID or name
      def get(id_or_alias)
        api_get(path(:templates, id_or_alias))
      end

      # @return [Hash] { total_count:, templates: [{ template_id:, name: }] }
      def list(count: DEFAULT_PAGE_SIZE, offset: 0)
        api_get(path(:templates), pagination_query(count, offset))
      end

      # @return [Enumerator] all templates, fetched page by page
      def each(page_size: DEFAULT_PAGE_SIZE, &block)
        iterate(:templates, page_size, nil, block) { |count, offset| list(count: count, offset: offset) }
      end

      # @return [Hash] { template_id:, name: }
      def create(name:, subject: nil, html_body: nil, text_body: nil, associated_server_id: nil)
        require_value!(:name, name)
        body = { "Name" => name, "Subject" => subject, "HtmlBody" => html_body,
                 "TextBody" => text_body, "AssociatedServerId" => associated_server_id }
        api_post(path(:templates), Util.compact(body))
      end

      # Replaces the whole template. The API blanks every field that is not sent,
      # so all four attributes are required. Use #patch to change a single field.
      def update(id_or_alias, name:, subject:, html_body:, text_body:)
        require_value!(:name, name)
        api_put(path(:templates, id_or_alias), {
                  "Name" => name, "Subject" => subject.to_s, "HtmlBody" => html_body.to_s, "TextBody" => text_body.to_s
                })
      end

      # Reads the template and updates only the given attributes.
      # Not atomic: a concurrent change between the read and the write is overwritten.
      def patch(id_or_alias, **changes)
        Util.assert_known_keys!(changes.keys, %i[name subject html_body text_body], "template")
        current = get(id_or_alias)
        attributes = %i[name subject html_body text_body].to_h { |key| [key, current[key]] }
        update(id_or_alias, **attributes, **changes)
      end

      def delete(id_or_alias)
        api_delete(path(:templates, id_or_alias))
      end

      # Renders a template without saving or sending anything.
      # @return [Hash] { all_content_is_valid:, subject: {...}, html_body: {...}, text_body: {...},
      #   suggested_template_model: {...} }
      def validate(subject: nil, html_body: nil, text_body: nil, test_render_model: nil)
        if [subject, html_body, text_body].all? { |part| Util.blank?(part) }
          raise ArgumentError, "At least one of subject, html_body or text_body is required"
        end

        body = Util.compact("Subject" => subject, "HtmlBody" => html_body, "TextBody" => text_body,
                            "TestRenderModel" => test_render_model)
        Serializer.from_api(connection.post(path(:templates, :validate), body, idempotent: true))
      end
    end
  end
end
