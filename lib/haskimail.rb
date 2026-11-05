# frozen_string_literal: true

require_relative "haskimail/version"
require_relative "haskimail/errors"
require_relative "haskimail/util"
require_relative "haskimail/secret"
require_relative "haskimail/configuration"
require_relative "haskimail/serializer"
require_relative "haskimail/response_handler"
require_relative "haskimail/connection"
require_relative "haskimail/paginator"
require_relative "haskimail/attachment"
require_relative "haskimail/resources/base"
require_relative "haskimail/resources/emails"
require_relative "haskimail/resources/templates"
require_relative "haskimail/resources/messages"
require_relative "haskimail/resources/bounces"
require_relative "haskimail/resources/message_streams"
require_relative "haskimail/resources/stats"
require_relative "haskimail/resources/webhooks"
require_relative "haskimail/resources/inbound_rules"
require_relative "haskimail/resources/suppressions"
require_relative "haskimail/resources/servers"
require_relative "haskimail/resources/domains"
require_relative "haskimail/resources/account_templates"
require_relative "haskimail/clients"
require_relative "haskimail/webhooks"

# Ruby SDK for the Haskimail transactional email API (https://haskimail.ru/developer).
module Haskimail
  # Send-only test token: the API validates the request but sends nothing.
  TEST_TOKEN = "HASKIMAIL_API_TEST"

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      config
    end

    def reset_config!
      @config = Configuration.new
    end

    # @return [Haskimail::ServerClient] built from the global configuration
    def server_client(token = nil, **options)
      ServerClient.new(token, **options)
    end

    # @return [Haskimail::AccountClient] built from the global configuration
    def account_client(token = nil, **options)
      AccountClient.new(token, **options)
    end
  end
end
