# frozen_string_literal: true

module Haskimail
  module Resources
    # Account-level template operations (account token).
    class AccountTemplates < Base
      # Moves (not copies!) all templates from one server to another.
      # Call with perform_changes: false first to preview what would be moved.
      # @return [Hash] { total_count:, templates: [{ template_id:, name: }] }
      def push(source_server_id:, destination_server_id:, perform_changes:)
        require_boolean!(:perform_changes, perform_changes)
        require_value!(:source_server_id, source_server_id)
        require_value!(:destination_server_id, destination_server_id)
        if source_server_id.to_s == destination_server_id.to_s
          raise ArgumentError, "source and destination servers must differ"
        end

        api_put(path(:templates, :push), {
                  "SourceServerID" => source_server_id,
                  "DestinationServerID" => destination_server_id,
                  "PerformChanges" => perform_changes
                })
      end

      # Creates a template on any server of the account.
      def create(associated_server_id:, name:, subject: nil, html_body: nil, text_body: nil)
        server_templates.create(name: name, subject: subject, html_body: html_body,
                                text_body: text_body, associated_server_id: associated_server_id)
      end

      # Templates of all servers in the account.
      # @return [Hash] { total_count:, templates: [{ template_id:, name: }] }
      def list(count: Templates::DEFAULT_PAGE_SIZE, offset: 0)
        server_templates.list(count: count, offset: offset)
      end

      def each(page_size: Templates::DEFAULT_PAGE_SIZE, &)
        server_templates.each(page_size: page_size, &)
      end

      # Renders a template without saving or sending anything (see Templates#validate).
      def validate(**options)
        server_templates.validate(**options)
      end

      private

      def server_templates
        @server_templates ||= Templates.new(connection)
      end
    end
  end
end
