# frozen_string_literal: true

RSpec.describe Haskimail::Resources::Messages do
  let(:messages) { server_client.messages }

  describe "outbound" do
    it "maps Ruby filters to API query names and formats dates in MSK" do
      stub = stub_api(:get, "/messages", response: { "TotalCount" => 0, "Messages" => [] }, query: {
                        "count" => "50", "offset" => "0", "recipient" => "a@b.ru", "fromemail" => "shop@b.ru",
                        "tag" => "orders", "subject" => "Заказ", "messagestream" => "2081",
                        "fromdate" => "2026-10-01", "todate" => "2026-10-07 15:00:00"
                      })
      messages.outbound(count: 50, recipient: "a@b.ru", from_email: "shop@b.ru", tag: "orders", subject: "Заказ",
                        message_stream: 2081, from_date: Date.new(2026, 10, 1),
                        to_date: Time.utc(2026, 10, 7, 12, 0, 0))
      expect(stub).to have_been_requested
    end

    it "validates page_size eagerly" do
      expect { messages.each_outbound(page_size: 1000) }.to raise_error(ArgumentError, /page_size/)
    end

    it "rejects unknown filters and API limits", :aggregate_failures do
      expect do
        messages.outbound(recipent: "typo")
      end.to raise_error(ArgumentError, /Unknown filter option\(s\): recipent/)
      expect { messages.outbound(count: 501) }.to raise_error(ArgumentError, /count/)
      expect { messages.outbound(count: 500, offset: 9_600) }.to raise_error(ArgumentError, /10000/)
      expect { messages.outbound(from_date: "01.10.2026") }.to raise_error(ArgumentError, /Invalid date/)
      expect { messages.outbound(from_date: 123) }.to raise_error(ArgumentError, /Expected a Date/)
    end

    it "paginates and stops at the 10 000 window" do
      stub_api(:get, "/messages", query: hash_including("count" => "500"),
                                  response: { "TotalCount" => 50_000, "Messages" => Array.new(500) do
                                    { "MessageID" => "x" }
                                  end })
      expect(messages.each_outbound(page_size: 500).count).to eq(10_000)
      expect(a_request(:get, %r{/messages\?})).to have_been_made.times(20)
    end

    it "yields records when a block is given" do
      stub_api(:get, "/messages", query: hash_including({}),
                                  response: { "TotalCount" => 1, "Messages" => [{ "MessageID" => "m1" }] })
      ids = []
      messages.each_outbound(tag: "orders") { |m| ids << m[:message_id] }
      expect(ids).to eq(["m1"])
    end

    it "gets outbound details" do
      stub_api(:get, "/messages/6f1c/details", response: { "MessageID" => "6f1c", "Status" => "Sent" })
      expect(messages.outbound_details("6f1c")).to eq(message_id: "6f1c", status: "Sent")
    end
  end

  describe "opens and clicks" do
    it "lists opens" do
      stub_api(:get, "/messages/opens", query: { "count" => "100", "offset" => "0", "tag" => "t" },
                                        response: { "TotalCount" => 1, "Opens" => [{ "RecordType" => "Open", "Os" => "Windows" }] })
      expect(messages.opens(tag: "t")[:opens]).to eq([{ record_type: "Open", os: "Windows" }])
    end

    it "lists opens of one message without date filters" do
      stub_api(:get, "/messages/opens/abc", query: { "count" => "10", "offset" => "0" }, response: { "Opens" => [] })
      messages.opens_for("abc", count: 10)
      expect { messages.opens_for("abc", from_date: "2026-01-01") }.to raise_error(ArgumentError, /from_date/)
    end

    it "lists clicks and clicks of one message" do
      stub_api(:get, "/messages/clicks", query: hash_including("count" => "100"),
                                         response: { "Clicks" => [{ "OriginalLink" => "https://e.com" }] })
      stub_api(:get, "/messages/clicks/abc", query: hash_including({}), response: { "Clicks" => [] })
      expect(messages.clicks[:clicks].first[:original_link]).to eq("https://e.com")
      expect(messages.clicks_for("abc")).to eq(clicks: [])
    end

    it "iterates opens and clicks" do
      stub_api(:get, "/messages/opens", query: hash_including({}),
                                        response: { "TotalCount" => 1, "Opens" => [{ "A" => 1 }] })
      stub_api(:get, "/messages/clicks", query: hash_including({}),
                                         response: { "TotalCount" => 1, "Clicks" => [{ "A" => 2 }] })
      expect(messages.each_open.to_a).to eq([{ a: 1 }])
      expect(messages.each_click.to_a).to eq([{ a: 2 }])
    end
  end

  describe "inbound" do
    it "uses the T date separator and lowercase status" do
      stub = stub_api(:get, "/messages/inbound", response: { "TotalCount" => 0, "InboundMessages" => [] }, query: {
                        "count" => "100", "offset" => "0", "status" => "failed", "mailboxhash" => "ticket-42",
                        "fromdate" => "2026-09-01T15:00:00"
                      })
      messages.inbound(status: "Failed", mailbox_hash: "ticket-42", from_date: Time.utc(2026, 9, 1, 12))
      expect(stub).to have_been_requested
    end

    it "validates inbound filters", :aggregate_failures do
      expect { messages.inbound(status: "lost") }.to raise_error(ArgumentError, /status must be one of/)
      expect { messages.inbound(tag: "x") }.to raise_error(ArgumentError, /Unknown inbound filter/)
    end

    it "iterates inbound messages" do
      stub_api(:get, "/messages/inbound", query: hash_including({}),
                                          response: { "TotalCount" => 1, "InboundMessages" => [{ "MessageID" => "i1" }] })
      expect(messages.each_inbound.map { |m| m[:message_id] }).to eq(["i1"])
    end

    it "gets details, bypasses and retries" do
      id = "22c74902-a0c1-4511-804f-341342852c90"
      stub_api(:get, "/messages/inbound/#{id}/details", response: { "FromFull" => { "Email" => "a@b.ru" } })
      stub_api(:put, "/messages/inbound/#{id}/bypass", response: { "ErrorCode" => 0, "Message" => "bypassed" })
      stub_api(:put, "/messages/inbound/#{id}/retry", response: { "ErrorCode" => 0, "Message" => "rescheduled" })

      expect(messages.inbound_details(id)).to eq(from_full: { email: "a@b.ru" })
      expect(messages.bypass_inbound(id)[:message]).to eq("bypassed")
      expect(messages.retry_inbound(id)[:message]).to eq("rescheduled")
    end

    it "never retries bypass/retry (they would re-post the message to your webhook)" do
      stub = stub_api(:put, "/messages/inbound/i1/retry", status: 503, response: {})
      expect { messages.retry_inbound("i1") }.to raise_error(Haskimail::ServiceUnavailableError)
      expect(stub).to have_been_requested.once
    end

    it "raises NotFoundError for an unknown message" do
      stub_api(:get, "/messages/nope/details", status: 422, response: { "ErrorCode" => 701, "Message" => "Not found" })
      expect { messages.outbound_details("nope") }.to raise_error(Haskimail::UnprocessableEntityError) { |e|
        expect(e.code?(Haskimail::ErrorCodes::MESSAGE_NOT_FOUND)).to be(true)
      }
    end
  end
end
