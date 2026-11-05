# frozen_string_literal: true

require "haskimail"
require "mail"
require "active_support"
require "active_support/lazy_load_hooks"
require_relative "haskimail/rails/message_options"
require_relative "haskimail/rails/mail_converter"
require_relative "haskimail/rails/delivery_method"
require_relative "haskimail/rails/mailer_helpers"

Mail::Message.include(Haskimail::Rails::MailExtension)

ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :haskimail, Haskimail::Rails::DeliveryMethod
  include Haskimail::Rails::MailerHelpers
end

require_relative "haskimail/rails/railtie" if defined?(Rails::Railtie)
