# frozen_string_literal: true

module Haskimail
  module Rails
    # Helpers available in every ActionMailer::Base subclass.
    #
    #   class OrderMailer < ApplicationMailer
    #     def created(order)
    #       haskimail tag: "orders", metadata: { order_id: order.id }, message_stream: "2081"
    #       mail to: order.email, subject: "Заказ №#{order.number} оформлен"
    #     end
    #
    #     def welcome(user)
    #       haskimail_template "welcome", model: { "{{name}}" => user.name }, to: user.email
    #     end
    #   end
    module MailerHelpers
      # Sets Haskimail options (tag, metadata, message_stream, track_opens,
      # track_links, template, template_model) for the message being built.
      def haskimail(**options)
        message.haskimail.assign(options)
      end

      # Sends a Haskimail template instead of a rendered view. The subject comes
      # from the template unless `subject:` is given.
      # @param template [Integer, String] template ID or alias
      # @param model [Hash] placeholders, e.g. { "{{name}}" => "Иван" }
      # @param headers [Hash] regular ActionMailer headers (to:, from:, cc:, subject:, ...)
      def haskimail_template(template, model: {}, **headers)
        if (stray = headers.keys.grep_v(Symbol)).any?
          raise ArgumentError, "Unexpected header(s) #{stray.inspect}: pass the template model as model: { ... }"
        end

        haskimail(template: template, template_model: model)
        # A blank subject stops ActionMailer from adding its default i18n subject.
        mail({ subject: "" }.merge(headers)) do |format|
          format.text { render plain: "" }
        end
      end
    end
  end
end
