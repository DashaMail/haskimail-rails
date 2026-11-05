# frozen_string_literal: true

RSpec.describe Haskimail::Resources::Emails do
  let(:client) { server_client }
  let(:sent) do
    { "To" => "ivan@example.com", "SubmittedAt" => "2026-10-07 14:30:12",
      "MessageID" => "6f1c0b2d", "ErrorCode" => 0, "Message" => "OK" }
  end

  describe "#deliver" do
    it "sends a fully featured message and returns a Ruby-style hash" do
      stub = stub_api(:post, "/email", response: sent, body: {
                        "From" => "Магазин <shop@example.com>",
                        "To" => "ivan@example.com",
                        "Cc" => "cc@example.com",
                        "Subject" => "Ваш заказ №1042 оформлен",
                        "HtmlBody" => "<p>Здравствуйте!</p>",
                        "TextBody" => "Здравствуйте!",
                        "Tag" => "orders",
                        "ReplyTo" => "support@example.com",
                        "Headers" => [{ "Name" => "X-Order-Id", "Value" => "1042" }],
                        "TrackOpens" => true,
                        "TrackLinks" => false,
                        "Metadata" => { "order_id" => "1042" },
                        "MessageStream" => "2081"
                      })

      result = client.deliver(
        from: "Магазин <shop@example.com>", to: "ivan@example.com", cc: "cc@example.com",
        subject: "Ваш заказ №1042 оформлен", html_body: "<p>Здравствуйте!</p>", text_body: "Здравствуйте!",
        tag: "orders", reply_to: "support@example.com", headers: { "X-Order-Id" => 1042 },
        track_opens: true, track_links: false, metadata: { "order_id" => "1042" }, message_stream: "2081"
      )

      expect(stub).to have_been_requested
      expect(result).to eq(to: "ivan@example.com", submitted_at: "2026-10-07 14:30:12",
                           message_id: "6f1c0b2d", error_code: 0, message: "OK")
    end

    it "accepts the exact API field names" do
      stub = stub_api(:post, "/email", response: sent,
                                       body: { "From" => "a@example.com", "To" => "b@example.com", "TextBody" => "Hi" })
      client.deliver("From" => "a@example.com", "To" => "b@example.com", "TextBody" => "Hi")
      expect(stub).to have_been_requested
    end

    it "accepts headers as a list of name/value pairs" do
      stub = stub_api(:post, "/email", response: sent, body: hash_including(
        "Headers" => [{ "Name" => "Message-ID", "Value" => "<id@example.com>" }]
      ))
      client.deliver(from: "a@example.com", to: "b@example.com", text_body: "x",
                     headers: [{ name: "Message-ID", value: "<id@example.com>" }])
      expect(stub).to have_been_requested
    end

    it "serializes Haskimail::Attachment objects" do
      attachment = Haskimail::Attachment.new(name: "a.txt", content: "hello")
      stub = stub_api(:post, "/email", response: sent, body: hash_including(
        "Attachments" => [{ "Name" => "a.txt", "Content" => "aGVsbG8=", "ContentType" => "text/plain" }]
      ))
      client.deliver(from: "a@example.com", to: "b@example.com", text_body: "x", attachments: [attachment])
      expect(stub).to have_been_requested
    end

    it "applies default_message_stream when none is given" do
      stub = stub_api(:post, "/email", response: sent, body: hash_including("MessageStream" => "2081"))
      server_client(default_message_stream: 2081).deliver(from: "a@example.com", to: "b@example.com", text_body: "x")
      expect(stub).to have_been_requested
    end

    it "keeps an explicit message_stream over the default" do
      stub = stub_api(:post, "/email", response: sent, body: hash_including("MessageStream" => "1"))
      server_client(default_message_stream: "2081")
        .deliver(from: "a@example.com", to: "b@example.com", text_body: "x", message_stream: "1")
      expect(stub).to have_been_requested
    end

    it "raises UnprocessableEntityError with the API error code" do
      stub_api(:post, "/email", status: 422,
                                response: { "ErrorCode" => 1226, "Message" => "MessageStream doesn't match api key" })
      expect { client.deliver(from: "a@example.com", to: "b@example.com", text_body: "x") }
        .to raise_error(Haskimail::UnprocessableEntityError) { |e| expect(e.error_code).to eq(1226) }
    end

    it "validates required fields before calling the API", :aggregate_failures do
      expect { client.deliver(to: "b@example.com", text_body: "x") }.to raise_error(ArgumentError, /From is required/)
      expect { client.deliver(from: "a@example.com", text_body: "x") }.to raise_error(ArgumentError, /To is required/)
      expect { client.deliver(from: "a@example.com", to: "b@example.com") }
        .to raise_error(ArgumentError, /html_body or text_body/)
      expect { client.deliver(from: "a@example.com", to: "b@example.com", template_alias: "x") }
        .to raise_error(ArgumentError, /deliver_with_template/)
      expect { client.deliver("not a hash") }.to raise_error(ArgumentError, /must be a Hash/)
      expect(a_request(:any, /haskimail/)).not_to have_been_made
    end

    it "rejects header injection", :aggregate_failures do
      base = { from: "a@example.com", to: "b@example.com", text_body: "x" }
      expect { client.deliver(**base, headers: { "X-A" => "1\r\nBcc: evil@example.com" }) }
        .to raise_error(ArgumentError, /Invalid header/)
      expect { client.deliver(**base, headers: { "X-A:B" => "1" }) }.to raise_error(ArgumentError, /Invalid header/)
      expect { client.deliver(**base, headers: ["X-A: 1"]) }.to raise_error(ArgumentError, /must be a Hash/)
    end

    it "rejects forbidden attachment types", :aggregate_failures do
      base = { from: "a@example.com", to: "b@example.com", text_body: "x" }
      expect { client.deliver(**base, attachments: [{ name: "virus.EXE", content: "AA==" }]) }
        .to raise_error(ArgumentError, /\.exe/)
      expect { client.deliver(**base, attachments: ["file.pdf"]) }.to raise_error(ArgumentError, /Attachment/)
    end
  end

  describe "input normalization" do
    it "joins address arrays into comma-separated strings" do
      stub = stub_api(:post, "/email", response: sent, body: hash_including(
        "To" => "a@example.com, Пётр <p@example.com>", "Cc" => "c@example.com", "ReplyTo" => "r@example.com"
      ))
      client.deliver(from: "s@example.com", to: ["a@example.com", "Пётр <p@example.com>"], cc: ["c@example.com"],
                     reply_to: ["r@example.com"], text_body: "x")
      expect(stub).to have_been_requested
    end

    it "accepts snake_case String keys (params, HashWithIndifferentAccess)" do
      require "active_support/hash_with_indifferent_access"
      message = ActiveSupport::HashWithIndifferentAccess.new(from: "a@example.com", to: "b@example.com",
                                                             text_body: "x", message_stream: "2081")
      stub = stub_api(:post, "/email", response: sent, body: {
                        "From" => "a@example.com", "To" => "b@example.com", "TextBody" => "x", "MessageStream" => "2081"
                      })
      client.deliver(message)
      expect(stub).to have_been_requested
    end

    it "refuses ambiguous duplicate fields" do
      expect { client.deliver(from: "a@example.com", "From" => "evil@example.com", to: "b@example.com", text_body: "x") }
        .to raise_error(ArgumentError, /Duplicate field From/)
    end

    it "normalizes ContentID of hash attachments to a bare Content-ID" do
      stub = stub_api(:post, "/email", response: sent, body: hash_including(
        "Attachments" => [{ "Name" => "logo.png", "Content" => "UE5H", "ContentType" => "image/png", "ContentID" => "logo.png" },
                          { "Name" => "a.txt", "Content" => "YQ==", "ContentType" => "text/plain" }]
      ))
      client.deliver(from: "a@example.com", to: "b@example.com", html_body: '<img src="cid:logo.png">',
                     attachments: [{ name: "logo.png", content: "UE5H", content_type: "image/png", content_id: "cid:logo.png" },
                                   { name: "a.txt", content: "YQ==", content_type: "text/plain", content_id: "" }])
      expect(stub).to have_been_requested
    end

    it "keeps header names literal, even when they differ only in case" do
      stub = stub_api(:post, "/email", response: sent, body: hash_including(
        "Headers" => [{ "Name" => "x-a", "Value" => "1" }, { "Name" => "X-a", "Value" => "2" }]
      ))
      client.deliver(from: "a@example.com", to: "b@example.com", text_body: "x", headers: { "x-a" => 1, "X-a" => 2 })
      expect(stub).to have_been_requested
    end

    it "refuses two spellings of headers" do
      expect { client.deliver(from: "a@b.ru", to: "c@d.ru", text_body: "x", headers: {}, "Headers" => {}) }
        .to raise_error(ArgumentError, /Duplicate field Headers/)
    end

    it "requires name and content for hash attachments", :aggregate_failures do
      base = { from: "a@example.com", to: "b@example.com", text_body: "x" }
      expect { client.deliver(**base, attachments: [{ name: "a.txt" }]) }.to raise_error(ArgumentError, /name and content/)
      expect { client.deliver(**base, attachments: [{ content: "YWJj" }]) }.to raise_error(ArgumentError, /name and content/)
    end

    it "rejects hash attachments whose content is not Base64" do
      expect do
        client.deliver(from: "a@example.com", to: "b@example.com", text_body: "x",
                       attachments: [{ name: "a.txt", content: "plain text", content_type: "text/plain" }])
      end.to raise_error(ArgumentError, /strict Base64/)
    end
  end

  describe "#deliver_batch" do
    it "posts a JSON array and returns per-message results" do
      response = [sent, { "To" => "bad", "MessageID" => nil, "ErrorCode" => 6, "Message" => "Некорректный" }]
      stub = stub_api(:post, "/email/batch", response: response, body: [
                        { "From" => "a@example.com", "To" => "ivan@example.com", "TextBody" => "1" },
                        { "From" => "a@example.com", "To" => "bad", "TextBody" => "2" }
                      ])
      results = client.deliver_batch([
                                       { from: "a@example.com", to: "ivan@example.com", text_body: "1" },
                                       { from: "a@example.com", to: "bad", text_body: "2" }
                                     ])
      expect(stub).to have_been_requested
      expect(results.map { |r| r[:error_code] }).to eq([0, 6])
    end

    it "allows template messages in a plain batch" do
      stub = stub_api(:post, "/email/batch", response: [sent])
      client.deliver_batch([{ from: "a@example.com", to: "b@example.com", template_id: 1 }])
      expect(stub).to have_been_requested
    end

    it "validates the batch size", :aggregate_failures do
      message = { from: "a@example.com", to: "b@example.com", text_body: "x" }
      expect { client.deliver_batch([]) }.to raise_error(ArgumentError, /empty/)
      expect { client.deliver_batch(message) }.to raise_error(ArgumentError, /Array/)
      expect { client.deliver_batch([message] * 501) }.to raise_error(ArgumentError, /at most 500/)
    end
  end

  describe "#deliver_with_template" do
    it "sends TemplateModel keys verbatim" do
      stub = stub_api(:post, "/email/withTemplate", response: sent, body: {
                        "TemplateId" => 4521, "TemplateModel" => { "{{name}}" => "Иван", "{{order}}" => "1042" },
                        "From" => "shop@example.com", "To" => "ivan@example.com"
                      })
      client.deliver_with_template(template_id: 4521, template_model: { "{{name}}" => "Иван", "{{order}}" => "1042" },
                                   from: "shop@example.com", to: "ivan@example.com")
      expect(stub).to have_been_requested
    end

    it "requires a template" do
      expect { client.deliver_with_template(from: "a@example.com", to: "b@example.com") }
        .to raise_error(ArgumentError, /template_id or template_alias/)
    end
  end

  describe "#deliver_batch_with_templates" do
    it "wraps messages in a Messages object" do
      stub = stub_api(:post, "/email/batchWithTemplates", response: [sent], body: {
                        "Messages" => [{ "TemplateAlias" => "welcome", "From" => "a@example.com", "To" => "b@example.com" }]
                      })
      client.deliver_batch_with_templates([{ template_alias: "welcome", from: "a@example.com", to: "b@example.com" }])
      expect(stub).to have_been_requested
    end
  end
end
