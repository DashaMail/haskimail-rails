# frozen_string_literal: true

RSpec.describe Haskimail::Connection do
  subject(:connection) do
    described_class.new(token: ApiHelpers::SERVER_TOKEN, token_header: "X-Haskimail-Server-Token", config: config)
  end

  let(:config) { Haskimail.config }

  describe "#initialize" do
    it "rejects blank tokens" do
      expect { described_class.new(token: " ", token_header: "X-Token", config: config) }
        .to raise_error(Haskimail::ConfigurationError, /X-Token is not set/)
    end

    it "rejects tokens with CR/LF (header injection)" do
      expect { described_class.new(token: "abc\r\nX-Evil: 1", token_header: "X-Token", config: config) }
        .to raise_error(Haskimail::ConfigurationError, /illegal characters/)
    end

    it "requires an https base_url" do
      config.base_url = "http://api.haskimail.ru"
      expect { connection }.to raise_error(Haskimail::ConfigurationError, /https/)
    end

    it "rejects credentials in base_url" do
      config.base_url = "https://user:pass@api.haskimail.ru"
      expect { connection }.to raise_error(Haskimail::ConfigurationError, /credentials/)
    end

    it "rejects malformed base_url" do
      config.base_url = "https://exa mple.com"
      expect { connection }.to raise_error(Haskimail::ConfigurationError, /Invalid base_url/)
    end

    it "honours a base_url with a path prefix" do
      config.base_url = "https://proxy.example.com/haskimail/"
      stub = stub_request(:get, "https://proxy.example.com/haskimail/servers").to_return(body: "{}")
      connection.get("/servers")
      expect(stub).to have_been_requested
    end
  end

  describe "request headers and body" do
    it "sends JSON with auth, accept and user-agent headers" do
      stub = stub_request(:post, "#{ApiHelpers::BASE_URL}/email")
             .with(
               body: { "From" => "a@example.com" }.to_json,
               headers: {
                 "Accept" => "application/json",
                 "Content-Type" => "application/json; charset=utf-8",
                 "X-Haskimail-Server-Token" => ApiHelpers::SERVER_TOKEN,
                 "User-Agent" => %r{\Ahaskimail-rails/#{Haskimail::VERSION} ruby/}
               }
             ).to_return(body: '{"ErrorCode":0}')

      connection.post("/email", { "From" => "a@example.com" })
      expect(stub).to have_been_requested
    end

    it "appends user_agent_suffix" do
      config.user_agent_suffix = "my-app/2.0"
      stub = stub_request(:get, "#{ApiHelpers::BASE_URL}/x").with(headers: { "User-Agent" => %r{my-app/2\.0\z} })
      connection.get("/x")
      expect(stub).to have_been_requested
    end

    it "encodes query parameters and drops nils" do
      stub = stub_request(:get, "#{ApiHelpers::BASE_URL}/messages?count=10&subject=%D0%97%D0%B0%D0%BA%D0%B0%D0%B7+1")
      connection.get("/messages", query: { "count" => 10, "subject" => "Заказ 1", "tag" => nil })
      expect(stub).to have_been_requested
    end

    it "returns nil for an empty body" do
      stub_request(:delete, "#{ApiHelpers::BASE_URL}/x").to_return(status: 200, body: "")
      expect(connection.delete("/x")).to be_nil
    end

    it "works without persistent connections" do
      config.persistent_connections = false
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(body: '{"A":1}')
      expect(connection.get("/x")).to eq("A" => 1)
    end
  end

  describe "error mapping" do
    {
      401 => Haskimail::UnauthorizedError,
      403 => Haskimail::ForbiddenError,
      404 => Haskimail::NotFoundError,
      413 => Haskimail::PayloadTooLargeError,
      422 => Haskimail::UnprocessableEntityError,
      429 => Haskimail::RateLimitError,
      500 => Haskimail::InternalServerError,
      502 => Haskimail::ServerError,
      503 => Haskimail::ServiceUnavailableError,
      418 => Haskimail::ApiError
    }.each do |status, klass|
      it "raises #{klass} for HTTP #{status}" do
        config.max_retries = 0
        stub_request(:post, "#{ApiHelpers::BASE_URL}/email")
          .to_return(status: status, body: '{"ErrorCode": 6, "Message": "Некорректный email"}')

        expect { connection.post("/email", {}) }.to raise_error(klass) { |error|
          expect(error.status).to eq(status)
          expect(error.error_code).to eq(6)
          expect(error.code?(Haskimail::ErrorCodes::INVALID_EMAIL)).to be(true)
          expect(error.message).to eq("Некорректный email (HTTP #{status}, ErrorCode 6)")
          expect(error.body).to eq("ErrorCode" => 6, "Message" => "Некорректный email")
        }
      end
    end

    it "normalizes a string ErrorCode to an Integer" do
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(status: 422, body: '{"ErrorCode":"1101","Message":"x"}')
      expect { connection.get("/x") }.to raise_error(Haskimail::UnprocessableEntityError) { |e|
        expect(e.code?(Haskimail::ErrorCodes::TEMPLATE_NOT_FOUND)).to be(true)
      }
    end

    it "raises on a non-zero ErrorCode in a 200 response" do
      stub_request(:delete, "#{ApiHelpers::BASE_URL}/x").to_return(body: '{"ErrorCode":12,"Message":"Not found"}')
      expect { connection.delete("/x") }.to raise_error(Haskimail::ApiError, /Not found \(HTTP 200, ErrorCode 12\)/)
    end

    it "does not treat ErrorCode 0 as an error" do
      stub_request(:delete, "#{ApiHelpers::BASE_URL}/x").to_return(body: '{"ErrorCode":0,"Message":"OK"}')
      expect(connection.delete("/x")).to eq("ErrorCode" => 0, "Message" => "OK")
    end

    it "keeps a truncated text body for non-JSON errors" do
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(status: 404, body: "<html>#{'x' * 1000}</html>")
      expect { connection.get("/x") }.to raise_error(Haskimail::NotFoundError) { |error|
        expect(error.body.bytesize).to eq(500)
        expect(error.error_code).to be_nil
      }
    end

    it "uses a generic message when the error body is empty" do
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(status: 404, body: "")
      expect { connection.get("/x") }.to raise_error(Haskimail::NotFoundError, "Haskimail API error (HTTP 404)")
    end

    it "raises InvalidResponseError for a non-JSON success body" do
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(status: 200, body: "<html>")
      expect { connection.get("/x") }.to raise_error(Haskimail::InvalidResponseError) { |error|
        expect(error.status).to eq(200)
      }
    end

    it "never retries certificate verification failures" do
      stub = stub_request(:get, "#{ApiHelpers::BASE_URL}/x")
             .to_raise(OpenSSL::SSL::SSLError.new("certificate verify failed"))
      expect { connection.get("/x") }.to raise_error(Haskimail::ConnectionError, /TLS error/)
      expect(stub).to have_been_requested.once
    end

    it "retries idempotent requests after a dropped TLS session, but not POSTs" do
      get = stub_request(:get, "#{ApiHelpers::BASE_URL}/x")
            .to_raise(OpenSSL::SSL::SSLError.new("unexpected eof while reading")).then.to_return(body: "{}")
      post = stub_request(:post, "#{ApiHelpers::BASE_URL}/email")
             .to_raise(OpenSSL::SSL::SSLError.new("unexpected eof while reading"))
      expect(connection.get("/x")).to eq({})
      expect { connection.post("/email", {}) }.to raise_error(Haskimail::ConnectionError)
      expect([get, post].map { |s| WebMock::RequestRegistry.instance.times_executed(s.request_pattern) }).to eq([2, 1])
    end
  end

  describe "retries" do
    it "retries idempotent requests on 503 and succeeds" do
      stub = stub_request(:get, "#{ApiHelpers::BASE_URL}/x")
             .to_return({ status: 503, body: "{}" }, { status: 200, body: '{"ok":true}' })
      expect(connection.get("/x")).to eq("ok" => true)
      expect(stub).to have_been_requested.twice
    end

    it "gives up after max_retries" do
      stub = stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(status: 500, body: "{}")
      expect { connection.get("/x") }.to raise_error(Haskimail::InternalServerError)
      expect(stub).to have_been_requested.times(3)
    end

    it "never retries a POST that may have been processed (no duplicate emails)" do
      stub = stub_request(:post, "#{ApiHelpers::BASE_URL}/email").to_return(status: 503, body: "{}")
      expect { connection.post("/email", {}) }.to raise_error(Haskimail::ServiceUnavailableError)
      expect(stub).to have_been_requested.once
    end

    it "never retries a POST after a read timeout" do
      stub = stub_request(:post, "#{ApiHelpers::BASE_URL}/email").to_raise(Net::ReadTimeout)
      expect { connection.post("/email", {}) }.to raise_error(Haskimail::TimeoutError)
      expect(stub).to have_been_requested.once
    end

    def fail_first_connect(error)
      calls = 0
      allow_any_instance_of(Net::HTTP).to receive(:start).and_wrap_original do |original, *args, &block| # rubocop:disable RSpec/AnyInstance
        calls += 1
        raise error if calls == 1

        original.call(*args, &block)
      end
    end

    [true, false].each do |persistent|
      it "retries a POST when the connection could not be opened (persistent: #{persistent})" do
        config.persistent_connections = persistent
        fail_first_connect(Errno::ECONNREFUSED)
        stub = stub_request(:post, "#{ApiHelpers::BASE_URL}/email").to_return(body: '{"ErrorCode":0}')
        expect(connection.post("/email", {})).to eq("ErrorCode" => 0)
        expect(stub).to have_been_requested.once
      end
    end

    it "raises ConnectionError when the connection never opens" do
      allow_any_instance_of(Net::HTTP).to receive(:start).and_raise(SocketError, "getaddrinfo") # rubocop:disable RSpec/AnyInstance
      expect { connection.post("/email", {}) }.to raise_error(Haskimail::ConnectionError, /SocketError: getaddrinfo/)
      expect(connection).to have_received(:pause).twice # rubocop:disable RSpec/SubjectStub
    end

    it "does not retry a POST when the network fails mid-request (it may have been sent)" do
      stub = stub_request(:post, "#{ApiHelpers::BASE_URL}/email").to_raise(Errno::EHOSTUNREACH)
      expect { connection.post("/email", {}) }.to raise_error(Haskimail::ConnectionError)
      expect(stub).to have_been_requested.once
    end

    it "does not retry DELETE after an uncertain failure" do
      stub = stub_request(:delete, "#{ApiHelpers::BASE_URL}/templates/1").to_return(status: 503, body: "{}")
      expect { connection.delete("/templates/1") }.to raise_error(Haskimail::ServiceUnavailableError)
      expect(stub).to have_been_requested.once
    end

    it "does not retry PUTs marked non-idempotent" do
      stub = stub_request(:put, "#{ApiHelpers::BASE_URL}/r").to_raise(Net::ReadTimeout)
      expect { connection.put("/r", nil, idempotent: false) }.to raise_error(Haskimail::TimeoutError)
      expect(stub).to have_been_requested.once
    end

    it "retries POSTs explicitly marked idempotent" do
      stub = stub_request(:post, "#{ApiHelpers::BASE_URL}/v")
             .to_return({ status: 500, body: "{}" }, { body: "{}" })
      connection.post("/v", {}, idempotent: true)
      expect(stub).to have_been_requested.twice
    end

    it "retries idempotent requests on connection resets" do
      stub = stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_raise(Errno::ECONNRESET).then.to_return(body: "{}")
      connection.get("/x")
      expect(stub).to have_been_requested.twice
    end

    it "wraps exhausted network failures in ConnectionError" do
      stub = stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_raise(SocketError.new("getaddrinfo"))
      expect { connection.get("/x") }.to raise_error(Haskimail::ConnectionError, /SocketError/)
      expect(stub).to have_been_requested.times(3)
    end

    it "maps timeouts to TimeoutError" do
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_raise(Net::OpenTimeout)
      expect { connection.get("/x") }.to raise_error(Haskimail::TimeoutError)
    end

    it "does not retry client errors" do
      stub = stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(status: 422, body: "{}")
      expect { connection.get("/x") }.to raise_error(Haskimail::UnprocessableEntityError)
      expect(stub).to have_been_requested.once
    end

    it "honours Retry-After (capped by retry_max_delay)" do
      config.retry_max_delay = 3
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x")
        .to_return({ status: 429, body: "{}", headers: { "Retry-After" => "120" } }, { body: "{}" })
      connection.get("/x")
      expect(connection).to have_received(:pause).with(3.0) # rubocop:disable RSpec/SubjectStub
    end

    it "uses exponential backoff with jitter" do
      config.retry_base_delay = 1
      delays = (1..4).map { |attempt| connection.send(:retry_delay, attempt, nil) }
      expect(delays[0]).to be_between(0.5, 1.0)
      expect(delays[1]).to be_between(1.0, 2.0)
      expect(delays[3]).to be_between(4.0, 8.0)
    end

    it "pauses with a real sleep when not stubbed" do
      conn = described_class.new(token: "token-123456789", token_header: "X", config: config)
      allow(conn).to receive(:pause).and_call_original
      allow(conn).to receive(:sleep)
      conn.send(:pause, 0.1)
      conn.send(:pause, 0)
      expect(conn).to have_received(:sleep).once.with(0.1)
    end
  end

  describe "connection pooling" do
    it "disables Net::HTTP's own silent retry of PUT/DELETE/GET" do
      http = connection.send(:build_http)
      expect([http.max_retries, http.verify_mode, http.min_version])
        .to eq([0, OpenSSL::SSL::VERIFY_PEER, OpenSSL::SSL::TLS1_2_VERSION])
    end

    it "reopens an idle keep-alive socket before sending (in the retry-safe connect phase)" do
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(body: "{}")
      now = 100.0
      allow(connection).to receive(:monotonic_now) { now } # rubocop:disable RSpec/SubjectStub
      connection.get("/x")
      first = Thread.current[described_class::THREAD_KEY].values.first[1]
      now += 1.0
      connection.get("/x")
      expect(Thread.current[described_class::THREAD_KEY].values.first[1]).to equal(first)
      now += described_class::MAX_IDLE_SECONDS + 0.1
      connection.get("/x")
      expect(Thread.current[described_class::THREAD_KEY].values.first[1]).not_to equal(first)
    end

    it "reuses one keep-alive connection per thread" do
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(body: "{}")
      connection.get("/x")
      first = Thread.current[described_class::THREAD_KEY].values.first[1]
      connection.get("/x")
      expect(Thread.current[described_class::THREAD_KEY].values.first[1]).to equal(first)
    end

    it "does not reuse a connection inherited across fork" do
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(body: "{}")
      connection.get("/x")
      pool = Thread.current[described_class::THREAD_KEY]
      key, (_pid, http, used) = pool.first
      pool[key] = [-1, http, used]
      connection.get("/x")
      expect(pool[key].first).to eq(Process.pid)
      expect(pool[key][1]).not_to equal(http)
    end

    it "discards the connection after a network error" do
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(body: "{}").then.to_raise(Errno::ECONNRESET)
      config.max_retries = 0
      connection.get("/x")
      expect { connection.get("/x") }.to raise_error(Haskimail::ConnectionError)
      expect(Thread.current[described_class::THREAD_KEY]).to be_empty
    end
  end

  describe "observability" do
    it "publishes ActiveSupport notifications without secrets" do
      require "active_support/notifications"
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x").to_return(body: "{}")
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("request.haskimail") { |*args| events << args.last }
      connection.get("/x")
      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(events).to eq([{ method: "GET", path: "/x", attempt: 1, status: 200 }])
    end

    it "logs method, path, status and duration only" do
      io = StringIO.new
      config.logger = Logger.new(io)
      stub_request(:get, "#{ApiHelpers::BASE_URL}/x?recipient=a%40b.ru").to_return(body: "{}")
      connection.get("/x", query: { "recipient" => "a@b.ru" })
      expect(io.string).to match(%r{\[Haskimail\] GET /x -> 200 \(\d+ms\)})
      expect(io.string).not_to include("a@b.ru", ApiHelpers::SERVER_TOKEN)
    end

    it "does not emit request notifications for connections that never opened" do
      require "active_support/notifications"
      allow_any_instance_of(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED) # rubocop:disable RSpec/AnyInstance
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("request.haskimail") { |*args| events << args.last }
      expect { connection.get("/x") }.to raise_error(Haskimail::ConnectionError, /ECONNREFUSED/)
      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(events).to be_empty
    end

    it "redacts the token in #inspect" do
      expect(connection.inspect).not_to include(ApiHelpers::SERVER_TOKEN)
      expect(connection.inspect).to include("serv…2222")
    end
  end
end
