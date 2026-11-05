# frozen_string_literal: true

require "rails/generators/base"

module Haskimail
  module Generators
    # rails generate haskimail:install
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Creates config/initializers/haskimail.rb"

      def copy_initializer
        template "haskimail.rb", "config/initializers/haskimail.rb"
      end

      def show_next_steps
        say <<~TEXT

          Haskimail is installed. Next steps:
            1. bin/rails credentials:edit  and add:
                 haskimail:
                   server_token: "..."
                   account_token: "..."     # optional, for servers/domains
                   webhook_password: "..."  # optional, Basic auth for webhooks
                   webhook_key: "..."       # optional, webhook signature key
            2. config/environments/production.rb:
                 config.action_mailer.delivery_method = :haskimail
        TEXT
      end
    end
  end
end
