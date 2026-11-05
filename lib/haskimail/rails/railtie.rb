# frozen_string_literal: true

module Haskimail
  module Rails
    # Wires Haskimail into a Rails application.
    #
    #   # config/application.rb (optional; credentials/ENV work too)
    #   config.haskimail.server_token = Rails.application.credentials.dig(:haskimail, :server_token)
    #   config.haskimail.default_message_stream = "2081"
    class Railtie < ::Rails::Railtie
      config.haskimail = ActiveSupport::OrderedOptions.new

      initializer "haskimail.configure" do |app|
        settings = app.config.haskimail.to_h
        unknown = settings.keys.map(&:to_sym) - Configuration::SETTINGS
        raise ConfigurationError, "Unknown config.haskimail option(s): #{unknown.join(', ')}" if unknown.any?

        Haskimail.configure do |config|
          settings.each { |key, value| config.public_send(:"#{key}=", value) }
        end
      end

      generators do
        require_relative "../../generators/haskimail/install/install_generator"
      end
    end
  end
end
