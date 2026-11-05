# frozen_string_literal: true

require "tempfile"

RSpec.describe Haskimail do
  describe ".configure" do
    it "sets global settings used by new clients" do
      described_class.configure do |config|
        config.server_token = "global-server-token"
        config.account_token = "global-account-token"
      end
      streams = stub_request(:get, "#{ApiHelpers::BASE_URL}/message-streams")
                .with(headers: { "X-Haskimail-Server-Token" => "global-server-token" }).to_return(body: "{}")
      domains = stub_request(:get, "#{ApiHelpers::BASE_URL}/domains?count=500&offset=0")
                .with(headers: { "X-Haskimail-Account-Token" => "global-account-token" }).to_return(body: "{}")

      described_class.server_client.message_streams.list
      described_class.account_client.domains.list
      expect([streams, domains]).to all(have_been_requested)
    end

    it "reads tokens from the environment" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("HASKIMAIL_SERVER_TOKEN", nil).and_return("env-token-123456")
      expect(Haskimail::Configuration.new.server_token).to eq("env-token-123456")
    end

    it "fails fast without a token" do
      expect { Haskimail::ServerClient.new }.to raise_error(Haskimail::ConfigurationError, /Server-Token is not set/)
      expect { Haskimail::AccountClient.new }.to raise_error(Haskimail::ConfigurationError, /Account-Token is not set/)
    end
  end

  describe Haskimail::Configuration do
    it "merges per-client overrides without mutating the global config" do
      client = Haskimail::ServerClient.new("token-abcdefghijkl", read_timeout: 3)
      expect(client.config.read_timeout).to eq(3)
      expect(Haskimail.config.read_timeout).to eq(30)
    end

    it "rejects unknown settings" do
      expect { Haskimail.config.merge(raed_timeout: 1) }.to raise_error(ArgumentError, /raed_timeout/)
    end

    it "never exposes tokens in #inspect" do
      Haskimail.config.server_token = "super-secret-server-token"
      Haskimail.config.account_token = "short"
      expect(Haskimail.config.inspect).not_to include("super-secret-server-token", "short\"")
      expect(Haskimail.config.inspect).to include("[REDACTED]")
      expect(Haskimail::ServerClient.new.inspect).not_to include("super-secret-server-token")
    end
  end

  describe Haskimail::ServerClient do
    it "exposes all server resources and memoizes them" do
      client = server_client
      %i[emails templates messages bounces message_streams stats webhooks inbound_rules suppressions].each do |name|
        expect(client.public_send(name)).to be_a(Haskimail::Resources::Base).and equal(client.public_send(name))
      end
      expect(client.emails.inspect).to eq("#<Haskimail::Resources::Emails>")
    end

    it "delegates the send shortcuts" do
      emails = instance_double(Haskimail::Resources::Emails, deliver: 1, deliver_batch: 2,
                                                             deliver_with_template: 3, deliver_batch_with_templates: 4)
      client = server_client
      allow(client).to receive(:emails).and_return(emails)
      expect([client.deliver({}), client.deliver_batch([]), client.deliver_with_template({}),
              client.deliver_batch_with_templates([])]).to eq([1, 2, 3, 4])
    end

    it "works with the send-only test token" do
      stub_request(:post, "#{ApiHelpers::BASE_URL}/email")
        .with(headers: { "X-Haskimail-Server-Token" => "HASKIMAIL_API_TEST" }).to_return(body: '{"ErrorCode":0}')
      result = described_class.new(Haskimail::TEST_TOKEN).deliver(from: "a@b.ru", to: "c@d.ru", text_body: "x")
      expect(result).to eq(error_code: 0)
    end
  end

  describe Haskimail::Serializer do
    it "converts requests to PascalCase with API acronyms" do
      input = { message_id: 1, content_id: 2, server_id: 3, source_server_id: 4, destination_server_id: 5, id: 6,
                associated_server_id: 7, template_id: 8, "Verbatim_Key" => 9, HtmlBody: 10, a__b: 11 }
      expect(described_class.to_api(input)).to eq(
        "MessageID" => 1, "ContentID" => 2, "ServerID" => 3, "SourceServerID" => 4, "DestinationServerID" => 5,
        "ID" => 6, "AssociatedServerId" => 7, "TemplateId" => 8, "Verbatim_Key" => 9, "HtmlBody" => 10, "AB" => 11
      )
    end

    it "does not touch opaque user data" do
      data = { metadata: { order_id: 1 }, template_model: { "{{user_name}}" => "x" } }
      expect(described_class.to_api(data)).to eq("Metadata" => { order_id: 1 },
                                                 "TemplateModel" => { "{{user_name}}" => "x" })
      expect(described_class.from_api("Metadata" => { "OrderId" => 1 })).to eq(metadata: { "OrderId" => 1 })
    end

    it "converts responses to snake_case symbols" do
      expect(described_class.from_api([{ "SPFTextValue" => { "record_type" => "TXT" }, "ReturnPathDomainVerified" => true,
                                         "Content-Type" => "x" }]))
        .to eq([{ spf_text_value: { record_type: "TXT" }, return_path_domain_verified: true, content_type: "x" }])
    end
  end

  describe Haskimail::Util do
    it "redacts secrets" do
      expect(described_class.redact(nil)).to be_nil
      expect(described_class.redact("short")).to eq("[REDACTED]")
      expect(described_class.redact("0123456789abcdef")).to eq("0123…cdef")
    end

    it "formats dates and times in Moscow time" do
      expect(described_class.format_date(nil)).to be_nil
      expect(described_class.format_date(Time.utc(2026, 1, 1, 21, 30))).to eq("2026-01-02")
      expect(described_class.format_date(DateTime.new(2026, 1, 1, 12))).to eq("2026-01-01")
      expect(described_class.format_datetime(nil)).to be_nil
      expect(described_class.format_datetime(Date.new(2026, 1, 1))).to eq("2026-01-01")
      expect(described_class.format_datetime("2026-01-01 10:00")).to eq("2026-01-01 10:00")
    end

    it "accepts objects that respond to #to_time" do
      timeish = Struct.new(:to_time).new(Time.utc(2026, 1, 1, 9))
      expect(described_class.format_date(timeish)).to eq("2026-01-01")
      expect(described_class.format_datetime(timeish)).to eq("2026-01-01 12:00:00")
      expect { described_class.format_datetime(:today) }.to raise_error(ArgumentError)
    end

    it "validates date strings", :aggregate_failures do
      expect { described_class.format_datetime("2026-13-01") }.to raise_error(ArgumentError, /Invalid date/)
      expect { described_class.format_datetime("2026-02-30") }.to raise_error(ArgumentError)
      expect { described_class.format_datetime("2026-10-01 24:00") }.to raise_error(ArgumentError)
      expect { described_class.format_date("2026-10-01 12:00") }.to raise_error(ArgumentError, /YYYY-MM-DD/)
      expect(described_class.format_datetime("2026-10-01T23:59:59")).to eq("2026-10-01T23:59:59")
    end

    it "detects blank values" do
      expect([nil, "", "  ", [], {}].map { |v| described_class.blank?(v) }).to all(be(true))
      expect([0, false, "x"].map { |v| described_class.blank?(v) }).to all(be(false))
    end
  end

  describe Haskimail::Attachment do
    it "builds from a file with a detected content type" do
      Tempfile.create(["invoice", ".pdf"]) do |file|
        file.binmode
        file.write("%PDF-1.4\xFF".b)
        file.flush
        attachment = described_class.from_file(file.path, content_id: "<cid:inv>")
        expect(attachment.to_h).to eq("Name" => File.basename(file.path), "Content" => "JVBERi0xLjT/",
                                      "ContentType" => "application/pdf", "ContentID" => "inv")
        expect(attachment.bytesize).to eq(9)
        expect(attachment.inspect).to include("application/pdf", "bytes=9")
        expect(attachment.inspect).not_to include("JVBER")
      end
    end

    it "normalizes and validates Content-IDs", :aggregate_failures do
      expect(described_class.normalize_content_id(" <CID:logo.png> ")).to eq("logo.png")
      expect(described_class.normalize_content_id("cid:<logo.png>")).to eq("logo.png")
      expect(described_class.normalize_content_id("cid:")).to be_nil
      expect(described_class.normalize_content_id(nil)).to be_nil
      expect { described_class.normalize_content_id("a b") }.to raise_error(ArgumentError, /Invalid ContentID/)
    end

    it "falls back to application/octet-stream" do
      expect(described_class.new(name: "data.unknownext", content: "x").content_type).to eq("application/octet-stream")
    end

    it "falls back when mini_mime is unavailable" do
      allow(described_class).to receive(:require).with("mini_mime").and_raise(LoadError)
      expect(described_class.guess_content_type("a.pdf")).to eq("application/octet-stream")
    end

    it "validates name and extension", :aggregate_failures do
      expect { described_class.new(name: " ", content: "x") }.to raise_error(ArgumentError, /name is required/)
      expect { described_class.new(name: "setup.msi", content: "x") }.to raise_error(ArgumentError, /\.msi/)
    end
  end

  describe Haskimail::Secret do
    subject(:secret) { described_class.new("very-secret-token-value") }

    it "hides the value everywhere except #reveal", :aggregate_failures do
      require "active_support/core_ext/object/json"
      expect(secret.reveal).to eq("very-secret-token-value")
      expect(secret.to_s).to eq("[REDACTED]")
      expect("#{secret}").to eq("[REDACTED]") # rubocop:disable Style/RedundantInterpolation
      expect(secret.inspect).to eq("#<Haskimail::Secret very…alue>")
      expect(secret.to_json).to eq('"[REDACTED]"')
      expect({ token: secret }.to_json).to eq('{"token":"[REDACTED]"}')
      expect(secret).to be_frozen
    end

    it "compares in constant time" do
      expect(secret).to eq(described_class.new("very-secret-token-value"))
      expect(secret).not_to eq(described_class.new("other"))
      expect(secret).not_to eq("very-secret-token-value")
      expect(secret.hash).to eq(described_class.new("very-secret-token-value").hash)
      expect(described_class.new("").empty?).to be(true)
    end
  end

  describe "serialization of clients" do
    it "never leaks tokens through to_json/as_json" do
      require "active_support/core_ext/object/json"
      described_class.config.server_token = "global-secret-token-123"
      client = server_client
      client.emails # memoize a resource too
      expect(client.to_json).not_to include(ApiHelpers::SERVER_TOKEN, "global-secret-token-123")
      expect(account_client.to_json).not_to include(ApiHelpers::ACCOUNT_TOKEN)
      expect(described_class.config.to_json).to include('"server_token":"[REDACTED]"').and(exclude("global-secret"))
      expect(Haskimail::Configuration.new.as_json["account_token"]).to be_nil
    end
  end

  describe Haskimail::Paginator do
    it "trusts total_count when the server returns smaller pages than requested" do
      paginator = described_class.new(items_key: :items, page_size: 500) do |_count, offset|
        { total_count: 250, items: Array.new(100) { |i| offset + i }.select { |i| i < 250 } }
      end
      expect(paginator.to_a).to eq((0...250).to_a)
    end

    it "requires a positive page size" do
      expect { described_class.new(items_key: :x, page_size: 0) { nil } }.to raise_error(ArgumentError)
    end

    it "stops on a short page even without total_count" do
      calls = []
      paginator = described_class.new(items_key: :items, page_size: 2) do |count, offset|
        calls << [count, offset]
        { items: offset.zero? ? [1, 2] : [3] }
      end
      expect(paginator.to_a).to eq([1, 2, 3])
      expect(calls).to eq([[2, 0], [2, 2]])
    end

    it "handles a nil page" do
      expect(described_class.new(items_key: :items, page_size: 5) { nil }.to_a).to eq([])
    end

    it "fetches nothing until iterated" do
      fetched = false
      described_class.new(items_key: :items, page_size: 5) { fetched = true }.each
      expect(fetched).to be(false)
    end
  end

  describe Haskimail::ApiError do
    it "builds a default message" do
      expect(described_class.new.message).to eq("Haskimail API error")
      expect(described_class.new(status: 500).message).to eq("Haskimail API error (HTTP 500)")
      expect(described_class.new(status: 500).retryable?).to be(true)
      expect(described_class.new(status: 422).retryable?).to be(false)
      expect(described_class.new.code?(nil)).to be(false)
    end
  end
end
