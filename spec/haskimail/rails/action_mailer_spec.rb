# frozen_string_literal: true

RSpec.describe "ActionMailer integration" do # rubocop:disable RSpec/DescribeClass
  let(:sent) { { "To" => "ivan@example.com", "MessageID" => "msg-1", "ErrorCode" => 0, "Message" => "OK" } }

  let(:mailer) do
    Class.new(ActionMailer::Base) do
      def self.name = "OrderMailer"

      default from: "Магазин <shop@example.com>"

      def created
        haskimail tag: "orders", metadata: { "order_id" => "1042" }, message_stream: "2081",
                  track_opens: true, track_links: false
        headers["X-Order-Id"] = "1042"
        attachments["invoice.pdf"] = { mime_type: "application/pdf", content: "%PDF".b }
        attachments.inline["logo.png"] = { mime_type: "image/png", content: "PNG".b }
        mail(to: ["ivan@example.com", "Пётр Петров <petr@example.com>"], cc: "cc@example.com",
             bcc: "audit@example.com", reply_to: "support@example.com", subject: "Заказ №1042 оформлен") do |format|
          format.text { render plain: "Здравствуйте! Заказ оформлен." }
          format.html { render html: "<p>Здравствуйте!</p>".html_safe }
        end
      end

      def plain_html
        mail(to: "ivan@example.com", subject: "HTML", content_type: "text/html", body: "<b>Привет</b>")
      end

      def plain_text
        mail(to: "ivan@example.com", subject: "Text", body: "Привет")
      end

      def smtp_headers
        headers["X-HM-Tag"] = "welcome"
        headers["X-HM-Metadata"] = '{"client_id": 12345}'
        headers["X-HM-TrackOpens"] = "true"
        headers["X-HM-No-Track-Click"] = "1"
        headers["X-HM-Domain"] = "example.com"
        headers["X-HM-MessageID"] = "order-1042"
        mail(to: "ivan@example.com", subject: "SMTP style", body: "x")
      end

      def bad_metadata_header
        headers["X-HM-Metadata"] = "[1, 2]"
        mail(to: "ivan@example.com", subject: "x", body: "x")
      end

      def invalid_metadata_json
        headers["X-HM-Metadata"] = "{nope"
        mail(to: "ivan@example.com", subject: "x", body: "x")
      end

      def no_track_opens
        headers["X-HM-No-Track-Opens"] = "yes"
        mail(to: "ivan@example.com", subject: "x", body: "x")
      end

      def welcome
        haskimail_template "welcome", model: { "{{name}}" => "Иван" }, to: "ivan@example.com"
      end

      def welcome_by_id
        haskimail_template 4521, to: "ivan@example.com", subject: "Override"
      end

      def template_with_unbraced_model
        haskimail_template "welcome", "{{name}}" => "Иван", to: "ivan@example.com"
      end

      def dangerous_attachment
        attachments["setup.exe"] = "MZ"
        mail(to: "ivan@example.com", subject: "x", body: "x")
      end
    end
  end

  before do
    ActionMailer::Base.delivery_method = :haskimail
    ActionMailer::Base.haskimail_settings = { api_token: ApiHelpers::SERVER_TOKEN }
    ActionMailer::Base.raise_delivery_errors = true
  end

  def last_payload
    payload = nil
    expect(a_request(:post, %r{api\.haskimail\.ru/email}).with { |req| payload = JSON.parse(req.body) })
      .to have_been_made
    payload
  end

  it "registers the :haskimail delivery method" do
    expect(ActionMailer::Base.delivery_methods).to include(haskimail: Haskimail::Rails::DeliveryMethod)
  end

  it "delivers a multipart message with options, headers and attachments" do
    stub_api(:post, "/email", response: sent)
    message = mailer.created.deliver_now

    payload = last_payload
    expect(payload).to include(
      "From" => "\"Магазин\" <shop@example.com>",
      "To" => "ivan@example.com, \"Пётр Петров\" <petr@example.com>",
      "Cc" => "cc@example.com",
      "Bcc" => "audit@example.com",
      "ReplyTo" => "support@example.com",
      "Subject" => "Заказ №1042 оформлен",
      "Tag" => "orders",
      "Metadata" => { "order_id" => "1042" },
      "MessageStream" => "2081",
      "TrackOpens" => true,
      "TrackLinks" => false
    )
    expect(payload["TextBody"]).to eq("Здравствуйте! Заказ оформлен.")
    expect(payload["HtmlBody"]).to eq("<p>Здравствуйте!</p>")
    expect(payload["Headers"]).to include({ "Name" => "X-Order-Id", "Value" => "1042" })
    expect(payload["Headers"].map { |h| h["Name"].downcase })
      .not_to include("from", "to", "subject", "content-type", "message-id")

    invoice, logo = payload["Attachments"].sort_by { |a| a["Name"] }
    expect(invoice).to eq("Name" => "invoice.pdf", "Content" => "JVBERg==", "ContentType" => "application/pdf")
    expect(logo).to include("Name" => "logo.png", "ContentType" => "image/png")
    # Bare Content-ID, as Haskimail uses ContentID verbatim (verified against the live API).
    expect(logo["ContentID"]).to match(/\A[^<>\s]+@[^<>\s]+\z/).and(satisfy { |id| !id.start_with?("cid:") })
    expect(payload["HtmlBody"]).to eq("<p>Здравствуйте!</p>")

    expect(message.haskimail.message_id).to eq("msg-1")
  end

  it "delivers single-part HTML and text messages" do
    stub_api(:post, "/email", response: sent)
    mailer.plain_html.deliver_now
    expect(last_payload).to include("HtmlBody" => "<b>Привет</b>").and(exclude("TextBody"))

    WebMock::RequestRegistry.instance.reset!
    mailer.plain_text.deliver_now
    expect(last_payload).to include("TextBody" => "Привет").and(exclude("HtmlBody"))
  end

  it "honours SMTP-style X-HM-* headers and passes the rest through" do
    stub_api(:post, "/email", response: sent)
    mailer.smtp_headers.deliver_now
    payload = last_payload
    expect(payload).to include("Tag" => "welcome", "Metadata" => { "client_id" => 12_345 }, "TrackOpens" => true,
                               "TrackLinks" => false)
    expect(payload["Headers"]).to contain_exactly({ "Name" => "X-HM-Domain", "Value" => "example.com" },
                                                  { "Name" => "X-HM-MessageID", "Value" => "order-1042" })
    expect(payload).not_to have_key("MessageStream")
  end

  it "disables open tracking via X-HM-No-Track-Opens" do
    stub_api(:post, "/email", response: sent)
    mailer.no_track_opens.deliver_now
    expect(last_payload).to include("TrackOpens" => false)
  end

  it "rejects malformed X-HM-Metadata", :aggregate_failures do
    expect { mailer.bad_metadata_header.deliver_now }.to raise_error(ArgumentError, /JSON object/)
    expect { mailer.invalid_metadata_json.deliver_now }.to raise_error(ArgumentError, /valid JSON/)
  end

  it "sends Haskimail templates by alias" do
    stub_api(:post, "/email/withTemplate", response: sent)
    mailer.welcome.deliver_now
    payload = nil
    expect(a_request(:post, %r{/email/withTemplate}).with { |req| payload = JSON.parse(req.body) }).to have_been_made
    expect(payload).to include("TemplateAlias" => "welcome", "TemplateModel" => { "{{name}}" => "Иван" },
                               "To" => "ivan@example.com")
    expect(payload.keys).not_to include("TextBody", "HtmlBody", "Subject")
  end

  it "sends Haskimail templates by id" do
    stub_api(:post, "/email/withTemplate", response: sent)
    mailer.welcome_by_id.deliver_now
    payload = nil
    expect(a_request(:post, %r{/email/withTemplate}).with { |req| payload = JSON.parse(req.body) }).to have_been_made
    expect(payload).to include("TemplateId" => 4521, "Subject" => "Override", "TemplateModel" => {})
  end

  it "catches a template model passed without model:" do
    expect { mailer.template_with_unbraced_model.deliver_now }.to raise_error(ArgumentError, /model:/)
  end

  it "raises API errors when raise_delivery_errors is on" do
    stub_api(:post, "/email", status: 422, response: { "ErrorCode" => 300, "Message" => "Invalid email request" })
    expect do
      mailer.plain_text.deliver_now
    end.to raise_error(Haskimail::UnprocessableEntityError, /Invalid email request/)
  end

  it "refuses forbidden attachments before calling the API" do
    expect { mailer.dangerous_attachment.deliver_now }.to raise_error(ArgumentError, /\.exe/)
    expect(a_request(:any, /haskimail/)).not_to have_been_made
  end

  it "falls back to the global token and supports return_response" do
    Haskimail.config.server_token = ApiHelpers::SERVER_TOKEN
    stub_api(:post, "/email", response: sent)
    method = Haskimail::Rails::DeliveryMethod.new(return_response: true, read_timeout: 5)
    message = Mail.new(from: "a@example.com", to: "b@example.com", subject: "s", body: "b")
    expect(method.deliver!(message)).to include(message_id: "msg-1")
    expect(method.inspect).to include("read_timeout").and(exclude(ApiHelpers::SERVER_TOKEN))
    method.settings[:api_token] = ApiHelpers::SERVER_TOKEN
    expect(method.to_json).to include("[REDACTED]", "read_timeout").and(exclude(ApiHelpers::SERVER_TOKEN))
  end

  it "accepts server_token as an alias and nil settings" do
    stub_api(:post, "/email", response: sent)
    method = Haskimail::Rails::DeliveryMethod.new("server_token" => ApiHelpers::SERVER_TOKEN)
    message = Mail.new(from: "a@example.com", to: "b@example.com", subject: "s", body: "b")
    expect(method.deliver!(message)).to equal(message)
    expect(Haskimail::Rails::DeliveryMethod.new(nil).settings).to eq({})
  end

  describe Haskimail::Rails::MessageOptions do
    subject(:options) { described_class.new }

    it "validates assignments", :aggregate_failures do
      expect { options.assign(tga: "x") }.to raise_error(ArgumentError, /Unknown haskimail/)
      expect { options.metadata = "x" }.to raise_error(ArgumentError)
      expect { options.track_opens = "yes" }.to raise_error(ArgumentError)
      expect { options.track_links = 1 }.to raise_error(ArgumentError)
      expect { options.template = 1.5 }.to raise_error(ArgumentError)
      expect { options.template = " " }.to raise_error(ArgumentError)
      expect { options.template_model = [] }.to raise_error(ArgumentError)
    end

    it "serializes to API fields" do
      options.assign(tag: :orders, message_stream: 2081, template: "welcome")
      expect(options.to_api).to eq("Tag" => "orders", "MessageStream" => "2081", "TemplateAlias" => "welcome",
                                   "TemplateModel" => {})
      expect(options.message_id).to be_nil
    end
  end

  describe Haskimail::Rails::MailConverter do
    it "works with messages that lack Haskimail options" do
      message = Mail.new(from: "a@example.com", to: "b@example.com", body: "x")
      allow(message).to receive(:respond_to?).and_call_original
      allow(message).to receive(:respond_to?).with(:haskimail).and_return(false)
      expect(described_class.call(message)).to include("From" => "a@example.com", "TextBody" => "x")
    end

    it "handles a missing From" do
      expect(described_class.call(Mail.new(to: "b@example.com", body: "x"))).not_to have_key("From")
    end
  end
end
