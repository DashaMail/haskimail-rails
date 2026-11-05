# frozen_string_literal: true

module ApiHelpers
  BASE_URL = "https://api.haskimail.ru"
  SERVER_TOKEN = "server-token-0000-1111-2222"
  ACCOUNT_TOKEN = "account-token-3333-4444-5555"

  def server_client(**options)
    Haskimail::ServerClient.new(SERVER_TOKEN, **options)
  end

  def account_client(**options)
    Haskimail::AccountClient.new(ACCOUNT_TOKEN, **options)
  end

  # Stubs a JSON endpoint and returns the WebMock stub for further assertions.
  def stub_api(method, path, response: {}, status: 200, token: :server, query: nil, body: nil, headers: {})
    header = token == :server ? "X-Haskimail-Server-Token" : "X-Haskimail-Account-Token"
    value = token == :server ? SERVER_TOKEN : ACCOUNT_TOKEN
    request_headers = { "Accept" => "application/json", header => value }
    stub = stub_request(method, "#{BASE_URL}#{path}")
    with = { headers: request_headers }
    with[:query] = query if query
    with[:body] = body if body
    stub.with(**with).to_return(
      status: status,
      body: response.is_a?(String) ? response : JSON.generate(response),
      headers: { "Content-Type" => "application/json" }.merge(headers)
    )
  end
end
