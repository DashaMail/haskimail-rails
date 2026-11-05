# frozen_string_literal: true

require "rack/mock"
require "digest"

RSpec.describe Haskimail::Webhooks do
  let(:key) { "account-webhook-key" }
  let(:bounce) do
    {
      "event" => "bounced", "recipient" => "old@example.com", "email" => "old@example.com",
      "message_id" => "a41d7c9e", "code" => "550", "description" => "550 5.1.1 does not exist",
      "error" => "550 5.1.1 does not exist", "bounce_category" => "hrd", "campaign_id" => "orders",
      "event_time" => "2026-10-07 14:30:15", "event_time_utc" => "2026-10-07 11:30:15",
      "secret" => Digest::MD5.hexdigest("old@example.coma41d7c9eaccount-webhook-key"),
      "custom_vars" => "{\"order_id\":\"1042\"}", "server_id" => 11_834, "stream_id" => "2081"
    }
  end

  describe ".parse" do
    it "parses events from JSON" do
      event = described_class.parse(JSON.generate(bounce))
      expect(event).to be_a(Haskimail::Webhooks::Event)
      expect(event).to have_attributes(
        type: :bounced, bounced?: true, hard_bounce?: true, soft_bounce?: false, delivered?: false,
        recipient: "old@example.com", message_id: "a41d7c9e", tag: "orders", server_id: 11_834, stream_id: "2081",
        bounce_category: :hard, bounce_code: "550", bounce_description: "550 5.1.1 does not exist",
        metadata: { "order_id" => "1042" }, occurred_at: Time.utc(2026, 10, 7, 11, 30, 15)
      )
      expect(event.idempotency_key).to eq("bounced:a41d7c9e:old@example.com:2026-10-07 11:30:15:")
      expect(event[:code]).to eq("550")
      expect(event.to_h).to eq(bounce)
      expect(event.inspect).to include(":bounced")
    end

    it "normalizes event names and complaint payload quirks" do
      event = described_class.parse("event" => "COMPLAINED", "custom_vars" => { "a" => 1 }, "stream_id" => 25,
                                    "event_time" => "2019-11-05 16:33:54", "recipient" => "x@y.ru")
      expect(event).to have_attributes(type: :complained, complained?: true, metadata: { "a" => 1 },
                                       stream_id: "25", occurred_at: Time.utc(2019, 11, 5, 13, 33, 54))
    end

    it "handles click and subscription change events" do
      click = described_class.parse("event" => "clicked", "url_original" => "https://e.com/a", "url_pers" => "https://e.com/b")
      expect(click).to have_attributes(clicked?: true, original_url: "https://e.com/a", clicked_url: "https://e.com/b")
      original_only = described_class.parse("event" => "clicked", "url_original" => "https://e.com/a")
      expect(original_only.idempotency_key).to end_with(":https://e.com/a")

      change = described_class.parse("event" => "subscriptionchange", "SuppressSending" => "true",
                                     "SuppressionReason" => "ManualSuppression", "message_id" => "")
      expect(change).to have_attributes(type: :subscription_change, subscription_change?: true,
                                        suppress_sending?: true, suppression_reason: "ManualSuppression",
                                        tag: nil, metadata: {}, occurred_at: nil, server_id: nil)
    end

    it "tolerates bad metadata and timestamps" do
      event = described_class.parse("event" => "opened", "custom_vars" => "{not json", "event_time" => "yesterday")
      expect(event.metadata).to eq({})
      expect(event.occurred_at).to be_nil
      expect(described_class.parse("event" => "opened", "custom_vars" => "[1]").metadata).to eq({})
    end

    it "parses inbound messages" do
      message = described_class.parse(
        "MessageID" => "22c7", "MessageStream" => 2083, "From" => "ivan@example.com", "FromName" => "Иван",
        "FromFull" => { "Email" => "ivan@example.com", "Name" => "Иван", "MailboxHash" => "" },
        "ToFull" => [{ "Email" => "hash+ticket-42@inbound.haskimail.ru", "Name" => "Поддержка", "MailboxHash" => "ticket-42" }],
        "Subject" => "Re: Заказ", "StrippedTextReply" => "Спасибо", "MailboxHash" => "ticket-42",
        "Headers" => [{ "Name" => "X-Spam-Score", "Value" => "0.3" }],
        "Attachments" => [{ "Name" => "check.pdf", "Content" => "JVBERg==", "ContentType" => "application/pdf",
                            "ContentLength" => 4, "ContentID" => "" }]
      )
      expect(message).to be_a(Haskimail::Webhooks::InboundMessage)
      expect(message).to have_attributes(type: :inbound, message_id: "22c7", message_stream: "2083",
                                         subject: "Re: Заказ", stripped_text_reply: "Спасибо",
                                         mailbox_hash: "ticket-42", spam_score: 0.3)
      expect(message.from.to_h).to eq(email: "ivan@example.com", name: "Иван", mailbox_hash: "")
      expect(message.to.first.mailbox_hash).to eq("ticket-42")
      expect(message.cc).to eq([])
      expect(message.header("x-spam-score")).to eq("0.3")
      attachment = message.attachments.first
      expect([attachment.name, attachment.read, attachment.inline?]).to eq(["check.pdf", "%PDF", false])
      expect(attachment.inspect).to include("check.pdf")
      expect(message.inspect).to include("attachments=1")
      expect(message[:Subject]).to eq("Re: Заказ")
    end

    it "builds the sender from flat fields when FromFull is missing" do
      message = described_class.parse("MessageID" => "1", "From" => "a@b.ru", "FromName" => "A")
      expect(message.from.to_h).to eq(email: "a@b.ru", name: "A", mailbox_hash: nil)
      expect(message.spam_score).to be_nil
    end

    it "rejects invalid payloads", :aggregate_failures do
      expect { described_class.parse("{") }.to raise_error(described_class::ParseError, /Invalid JSON/)
      expect { described_class.parse("[]") }.to raise_error(described_class::ParseError, /JSON object/)
      expect { described_class.parse("{}") }.to raise_error(described_class::ParseError, /Unrecognized/)
    end
  end

  describe "signature verification" do
    it "accepts a valid MD5 signature in any case" do
      expect(described_class.valid_signature?(JSON.generate(bounce), key: key)).to be(true)
      upper = described_class.parse(bounce.merge("secret" => bounce["secret"].upcase))
      expect(described_class.verify_signature!(upper, key: key)).to be_a(Haskimail::Webhooks::Event)
    end

    it "never treats an inbound payload as signed", :aggregate_failures do
      inbound = JSON.generate("MessageID" => "1", "FromFull" => {})
      expect(described_class.valid_signature?(inbound, key: key)).to be(false)
      expect { described_class.verify_signature!(inbound, key: key) }.to raise_error(Haskimail::WebhookVerificationError)
    end

    it "rejects a forged or missing signature or a blank key", :aggregate_failures do
      event = described_class.parse(bounce)
      expect(described_class.valid_signature?(event, key: "other-key")).to be(false)
      expect(described_class.valid_signature?(event, key: "")).to be(false)
      expect(described_class.valid_signature?(described_class.parse(bounce.except("secret")), key: key)).to be(false)
      expect(described_class.valid_signature?(described_class.parse(bounce.merge("secret" => "abc")),
                                              key: key)).to be(false)
      expect { described_class.verify_signature!(event, key: "other-key") }
        .to raise_error(Haskimail::WebhookVerificationError)
    end

    it "signs events without a message with an empty message_id" do
      payload = { "event" => "subscriptionchange", "recipient" => "a@b.ru", "message_id" => "",
                  "secret" => Digest::MD5.hexdigest("a@b.ru#{key}") }
      expect(described_class.valid_signature?(payload.to_json, key: key)).to be(true)
    end
  end

  describe ".valid_basic_auth?" do
    def header(user, password)
      "Basic #{["#{user}:#{password}"].pack('m0')}"
    end

    it "checks credentials" do
      expect(described_class.valid_basic_auth?(header("hm", "p:ss"), username: "hm", password: "p:ss")).to be(true)
      expect(described_class.valid_basic_auth?(header("hm", "bad"), username: "hm", password: "p:ss")).to be(false)
      expect(described_class.valid_basic_auth?(header("xx", "p:ss"), username: "hm", password: "p:ss")).to be(false)
      expect(described_class.valid_basic_auth?("Bearer abc", username: "hm", password: "p")).to be(false)
      expect(described_class.valid_basic_auth?(nil, username: "hm", password: "p")).to be(false)
    end
  end

  describe Haskimail::Webhooks::Endpoint do
    let(:received) { [] }
    let(:app) { described_class.new(signature_key: key, username: "hm", password: "secret") { |e| received << e } }
    let(:auth) { { "HTTP_AUTHORIZATION" => "Basic #{['hm:secret'].pack('m0')}" } }

    def post(app, body, env = {})
      Rack::MockRequest.new(app).post("/", { input: body, "CONTENT_TYPE" => "application/json" }.merge(env))
    end

    it "accepts a signed, authenticated event and calls the handler" do
      response = post(app, JSON.generate(bounce), auth)
      expect(response.status).to eq(200)
      expect(received.map(&:type)).to eq([:bounced])
    end

    it "publishes ActiveSupport notifications" do
      require "active_support/notifications"
      payloads = []
      subscriber = ActiveSupport::Notifications.subscribe("webhook.haskimail") { |*args| payloads << args.last }
      post(app, JSON.generate(bounce), auth)
      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(payloads.first[:type]).to eq(:bounced)
      expect(payloads.first[:event].message_id).to eq("a41d7c9e")
    end

    it "rejects bad credentials with 401" do
      response = post(app, JSON.generate(bounce), "HTTP_AUTHORIZATION" => "Basic #{['hm:wrong'].pack('m0')}")
      expect(response.status).to eq(401)
      expect(response.headers["www-authenticate"]).to include("Basic")
      expect(received).to be_empty
    end

    it "rejects a bad signature with 403 (Haskimail will not retry)" do
      response = post(app, JSON.generate(bounce.merge("secret" => "0" * 32)), auth)
      expect(response.status).to eq(403)
      expect(received).to be_empty
    end

    it "accepts unsigned inbound messages (protected by Basic auth)" do
      response = post(app, JSON.generate("MessageID" => "1", "FromFull" => {}), auth)
      expect(response.status).to eq(200)
      expect(received.first).to be_a(Haskimail::Webhooks::InboundMessage)
    end

    it "returns 400 for malformed JSON, 405 for other methods and 413 for huge bodies", :aggregate_failures do
      expect(post(app, "{oops", auth).status).to eq(400)
      expect(Rack::MockRequest.new(app).get("/").status).to eq(405)
      small = described_class.new(max_body_bytes: 10, username: "hm", password: "secret")
      expect(post(small, JSON.generate(bounce), auth).status).to eq(413)
    end

    it "returns 500 when the handler fails so Haskimail retries" do
      logger = instance_double(Logger, error: nil)
      failing = described_class.new(logger: logger, allow_unauthenticated: true) { raise "boom" }
      expect(post(failing, JSON.generate(bounce)).status).to eq(500)
      expect(logger).to have_received(:error).with(/RuntimeError: boom/)
    end

    it "refuses to start without Basic auth unless explicitly opted out", :aggregate_failures do
      expect { described_class.new }.to raise_error(Haskimail::ConfigurationError, /Basic auth/)
      expect { described_class.new(signature_key: key) }.to raise_error(Haskimail::ConfigurationError, /allow_signature_only/)
      expect { described_class.new(signature_key: key, max_body_bytes: nil) }
        .to raise_error(Haskimail::ConfigurationError, /max_body_bytes/)
    end

    it "accepts anything only when explicitly allowed (development)" do
      open_app = described_class.new(allow_unauthenticated: true)
      expect(post(open_app, JSON.generate(bounce.merge("secret" => "forged"))).status).to eq(200)
      expect(post(open_app, JSON.generate("MessageID" => "1")).status).to eq(200)
    end

    it "still enforces a configured signature key with allow_unauthenticated" do
      dev_app = described_class.new(signature_key: key, allow_unauthenticated: true)
      expect(post(dev_app, JSON.generate(bounce.merge("secret" => "forged"))).status).to eq(403)
      expect(post(dev_app, JSON.generate("MessageID" => "1")).status).to eq(200)
    end

    it "rejects unsigned inbound messages when only a signature key is configured" do
      signed_only = described_class.new(signature_key: key, allow_signature_only: true) { |e| received << e }
      expect(post(signed_only, JSON.generate("MessageID" => "x", "From" => "attacker@evil.test")).status).to eq(403)
      expect(post(signed_only, JSON.generate(bounce)).status).to eq(200)
      expect(received.map(&:type)).to eq([:bounced])
    end

    it "accepts unsigned events when only Basic auth is configured" do
      basic_only = described_class.new(username: "hm", password: "secret") { |e| received << e }
      expect(post(basic_only, JSON.generate(bounce.except("secret")), auth).status).to eq(200)
    end

    it "works without ActiveSupport::Notifications" do
      hide_const("ActiveSupport::Notifications")
      expect(post(app, JSON.generate(bounce), auth).status).to eq(200)
      expect(received.size).to eq(1)
    end

    it "answers 400 (not 500) to an empty authenticated body" do
      response = app.call("REQUEST_METHOD" => "POST", "HTTP_AUTHORIZATION" => auth["HTTP_AUTHORIZATION"],
                          "rack.input" => StringIO.new(""))
      expect(response.first).to eq(400)
    end

    it "handles a missing rack.input" do
      response = app.call("REQUEST_METHOD" => "POST", "HTTP_AUTHORIZATION" => auth["HTTP_AUTHORIZATION"])
      expect(response.first).to eq(400)
    end

    it "requires username and password together" do
      expect { described_class.new(username: "hm") }.to raise_error(Haskimail::ConfigurationError)
    end

    it "does not leak secrets in #inspect or JSON" do
      require "active_support/core_ext/object/json"
      expect(app.inspect).to eq("#<Haskimail::Webhooks::Endpoint signed=true basic_auth=true>")
      expect(app.to_json).not_to include(key, "secret\"")
    end
  end
end
