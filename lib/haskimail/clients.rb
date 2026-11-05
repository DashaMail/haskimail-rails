# frozen_string_literal: true

module Haskimail
  # Shared client behaviour: configuration, lazily built resources, safe #inspect.
  class BaseClient
    attr_reader :config

    # @param token [String, nil] falls back to the global configuration
    # @param options [Hash] per-client overrides of Haskimail::Configuration settings
    def initialize(token = nil, **options)
      @config = Haskimail.config.merge(options)
      @connection = Connection.new(token: token || default_token, token_header: self.class::TOKEN_HEADER,
                                   config: @config)
    end

    def inspect
      "#<#{self.class.name} #{@connection.inspect}>"
    end
    alias to_s inspect

    def self.resource(name, klass)
      define_method(name) do
        @resources ||= {}
        @resources[name] ||= klass.new(@connection)
      end
    end
    private_class_method :resource
  end

  # Client for everything that belongs to one server: sending, templates,
  # messages, bounces, message streams, stats, webhooks, inbound rules, suppressions.
  #
  #   client = Haskimail::ServerClient.new(ENV["HASKIMAIL_SERVER_TOKEN"])
  #   client.deliver(from: "shop@example.com", to: "ivan@example.com", subject: "Hi", text_body: "Hi")
  class ServerClient < BaseClient
    TOKEN_HEADER = "X-Haskimail-Server-Token"

    resource :emails, Resources::Emails
    resource :templates, Resources::Templates
    resource :messages, Resources::Messages
    resource :bounces, Resources::Bounces
    resource :message_streams, Resources::MessageStreams
    resource :stats, Resources::Stats
    resource :webhooks, Resources::Webhooks
    resource :inbound_rules, Resources::InboundRules
    resource :suppressions, Resources::Suppressions

    # Shortcuts for the most common calls.
    def deliver(message) = emails.deliver(message)
    def deliver_batch(messages) = emails.deliver_batch(messages)
    def deliver_with_template(message) = emails.deliver_with_template(message)
    def deliver_batch_with_templates(messages) = emails.deliver_batch_with_templates(messages)

    private

    def default_token
      config.server_token
    end
  end

  # Client for account-wide management: servers, domains, moving templates.
  #
  #   account = Haskimail::AccountClient.new(ENV["HASKIMAIL_ACCOUNT_TOKEN"])
  #   account.domains.create("example.com")
  class AccountClient < BaseClient
    TOKEN_HEADER = "X-Haskimail-Account-Token"

    resource :servers, Resources::Servers
    resource :domains, Resources::Domains
    resource :templates, Resources::AccountTemplates

    private

    def default_token
      config.account_token
    end
  end
end
