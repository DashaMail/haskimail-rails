# frozen_string_literal: true

module Haskimail
  # Converts between idiomatic Ruby hashes and the PascalCase JSON of the API.
  #
  # Requests: snake_case keys (Symbols or Strings, e.g. from params or a
  # HashWithIndifferentAccess) are camelized (`:html_body` -> "HtmlBody",
  # "message_id" -> "MessageID"). Keys that already start with an uppercase
  # letter ("HtmlBody") are sent verbatim. Two keys that map to the same API
  # field raise ArgumentError instead of silently overwriting each other.
  #
  # Responses: keys become snake_case Symbols ("MessageID" -> :message_id,
  # "DKIMVerified" -> :dkim_verified).
  #
  # Values under "opaque" keys (Metadata, TemplateModel, ...) are user data and
  # are never transformed in either direction: their keys are template
  # placeholders such as "{{name}}" or arbitrary metadata names.
  module Serializer
    OPAQUE_KEYS = %w[Metadata TemplateModel TestRenderModel SuggestedTemplateModel].freeze

    REQUEST_KEY_OVERRIDES = {
      "id" => "ID",
      "message_id" => "MessageID",
      "content_id" => "ContentID",
      "server_id" => "ServerID",
      "source_server_id" => "SourceServerID",
      "destination_server_id" => "DestinationServerID"
    }.freeze

    module_function

    def to_api(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), out|
          api_key = api_key(key)
          raise ArgumentError, "Duplicate field #{api_key} (given as #{key.inspect})" if out.key?(api_key)

          out[api_key] = OPAQUE_KEYS.include?(api_key) ? val : to_api(val)
        end
      when Array then value.map { |item| to_api(item) }
      else value
      end
    end

    def from_api(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), out|
          out[ruby_key(key)] = OPAQUE_KEYS.include?(key.to_s) ? val : from_api(val)
        end
      when Array then value.map { |item| from_api(item) }
      else value
      end
    end

    def api_key(key)
      name = key.to_s
      return name if name.match?(/\A[A-Z]/)

      REQUEST_KEY_OVERRIDES.fetch(name) do
        name.split("_").map { |part| part.empty? ? part : part[0].upcase + part[1..] }.join
      end
    end

    def ruby_key(key)
      key.to_s
         .gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
         .gsub(/([a-z\d])([A-Z])/, '\1_\2')
         .tr("-", "_")
         .downcase
         .to_sym
    end
  end
end
