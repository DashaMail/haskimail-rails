# frozen_string_literal: true

# Haskimail: https://haskimail.ru/developer
#
# Tokens are read from HASKIMAIL_SERVER_TOKEN / HASKIMAIL_ACCOUNT_TOKEN by default;
# values from credentials take precedence when present.
Haskimail.configure do |config|
  credentials = Rails.application.credentials.haskimail || {}

  config.server_token = credentials[:server_token] if credentials[:server_token]
  config.account_token = credentials[:account_token] if credentials[:account_token]

  # Stream used when a message does not set one explicitly.
  # config.default_message_stream = "2081"

  # Network settings (seconds). Only requests that are safe to repeat are
  # retried, so an email is never sent twice.
  # config.open_timeout = 5
  # config.read_timeout = 30
  # config.max_retries = 2

  # config.logger = Rails.logger
end

# Send-only test token for development and test: the API validates requests
# but delivers nothing.
# Haskimail.config.server_token = Haskimail::TEST_TOKEN if Rails.env.development? || Rails.env.test?
