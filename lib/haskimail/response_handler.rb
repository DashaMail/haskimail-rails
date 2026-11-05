# frozen_string_literal: true

require "json"

module Haskimail
  # Turns a Net::HTTPResponse into parsed JSON or raises the matching error.
  module ResponseHandler
    MAX_ERROR_BODY = 500

    module_function

    # @return [Hash, Array, nil] parsed JSON body
    def call(response)
      status = response.code.to_i
      headers = response.each_header.to_h
      body = parse_body(response.body, status)

      if status.between?(200, 299)
        raise_for_error_code!(body, status, headers)
        return body
      end

      error_code = body.is_a?(Hash) ? integer(body["ErrorCode"]) : nil
      api_message = body.is_a?(Hash) ? body["Message"] : body
      raise ApiError.for(
        status: status,
        error_code: error_code,
        message: error_message(api_message, status, error_code),
        body: body,
        headers: headers
      )
    end

    # Some endpoints report failures as {"ErrorCode": N} even with HTTP 200.
    def raise_for_error_code!(body, status, headers)
      return unless body.is_a?(Hash)

      code = integer(body["ErrorCode"])
      return if code.nil? || code.zero?

      raise ApiError.new(error_message(body["Message"], status, code),
                         status: status, error_code: code, body: body, headers: headers)
    end

    def integer(value)
      value.nil? ? nil : Integer(value, exception: false)
    end

    def parse_body(raw, status)
      text = raw.to_s.dup.force_encoding(Encoding::UTF_8)
      return nil if text.strip.empty?

      JSON.parse(text)
    rescue JSON::ParserError
      raise InvalidResponseError.new("Haskimail returned invalid JSON (HTTP #{status})", status: status) if status < 300

      text.byteslice(0, MAX_ERROR_BODY).scrub
    end

    def error_message(api_message, status, error_code)
      details = ["HTTP #{status}"]
      details << "ErrorCode #{error_code}" if error_code
      text = api_message.to_s.strip
      text = "Haskimail API error" if text.empty?
      "#{text} (#{details.join(', ')})"
    end
  end
end
