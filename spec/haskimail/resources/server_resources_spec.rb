# frozen_string_literal: true

RSpec.describe "Server resources" do # rubocop:disable RSpec/DescribeClass
  let(:client) { server_client }

  describe Haskimail::Resources::Bounces do
    it "returns delivery stats" do
      stub_api(:get, "/deliverystats", response: { "Bounces" => [{ "Name" => "All", "Count" => 253 }] })
      expect(client.bounces.delivery_stats).to eq(bounces: [{ name: "All", count: 253 }])
    end

    it "lists bounces with camelCase query names and date-only filters" do
      stub = stub_api(:get, "/bounces", response: { "TotalCount" => 0, "Bounces" => [] }, query: {
                        "count" => "50", "offset" => "0", "type" => "HardBounce", "emailFilter" => "a@b.ru",
                        "messageID" => "m1", "messagestream" => "2081", "fromdate" => "2026-10-01",
                        "todate" => "2026-10-08", "tag" => "t"
                      })
      # 22:00 UTC on Oct 7 is already Oct 8 in Moscow.
      client.bounces.list(count: 50, type: "HardBounce", email_filter: "a@b.ru", message_id: "m1",
                          message_stream: "2081", from_date: "2026-10-01",
                          to_date: Time.utc(2026, 10, 7, 22, 0), tag: "t")
      expect(stub).to have_been_requested
      expect { client.bounces.list(subject: "x") }.to raise_error(ArgumentError, /Unknown bounce filter/)
    end

    it "skips nil filters and validates the type", :aggregate_failures do
      stub = stub_api(:get, "/bounces", query: { "count" => "500", "offset" => "0" }, response: {})
      client.bounces.list(tag: nil)
      expect(stub).to have_been_requested
      expect { client.bounces.list(type: "Hard") }.to raise_error(ArgumentError, /type must be one of/)
    end

    it "iterates bounces" do
      stub_api(:get, "/bounces", query: hash_including({}),
                                 response: { "TotalCount" => 1, "Bounces" => [{ "Email" => "x" }] })
      expect(client.bounces.each.to_a).to eq([{ email: "x" }])
    end
  end

  describe Haskimail::Resources::MessageStreams do
    let(:stream) do
      { "ID" => "2081", "ServerID" => 11_834, "Name" => "Заказы", "MessageStreamType" => "transactional",
        "ArchivedAt" => nil }
    end

    it "lists and gets streams" do
      stub_api(:get, "/message-streams", response: { "TotalCount" => 1, "MessageStreams" => [stream] })
      stub_api(:get, "/message-streams/2081", response: stream)
      expect(client.message_streams.list[:message_streams].first[:id]).to eq("2081")
      expect(client.message_streams.get("2081")).to include(server_id: 11_834, archived_at: nil)
    end

    it "creates a stream with a case-insensitive type" do
      stub = stub_api(:post, "/message-streams", response: stream,
                                                 body: { "ServerID" => 11_834, "Name" => "Заказы", "MessageStreamType" => "Broadcasts" })
      client.message_streams.create(name: "Заказы", message_stream_type: "broadcasts", server_id: 11_834)
      expect(stub).to have_been_requested
      expect { client.message_streams.create(name: "x", message_stream_type: "inbound") }
        .to raise_error(ArgumentError, /Transactional, Broadcasts/)
    end

    it "renames, archives and unarchives" do
      stub_api(:patch, "/message-streams/2081", body: { "Name" => "Новое" }, response: stream)
      stub_api(:post, "/message-streams/2081/archive",
               response: { "ID" => "2081", "ArchivedAt" => "2026-10-07 15:00:00", "ExpectedPurgeDate" => "2026-11-21 15:00:00" })
      stub_api(:post, "/message-streams/2081/unarchive", response: stream)

      client.message_streams.update("2081", name: "Новое")
      expect(client.message_streams.archive("2081")).to include(expected_purge_date: "2026-11-21 15:00:00")
      expect(client.message_streams.unarchive("2081")).to include(archived_at: nil)
      expect { client.message_streams.update("2081", name: " ") }.to raise_error(ArgumentError)
    end
  end

  describe Haskimail::Resources::Stats do
    it "fetches the overview with date filters" do
      stub_api(:get, "/stats", query: { "fromdate" => "2026-10-01", "todate" => "2026-10-07", "messagestream" => "2081" },
                               response: { "Sent" => 615, "BounceRate" => 10.41, "Unsubsribed" => 3 })
      result = client.stats.overview(from_date: Date.new(2026, 10, 1), to_date: "2026-10-07", message_stream: 2081)
      expect(result).to eq(sent: 615, bounce_rate: 10.41, unsubsribed: 3)
    end

    {
      sends: "/stats/sends", bounces: "/stats/bounces", spam_complaints: "/stats/spam", opens: "/stats/opens",
      clicks: "/stats/clicks", open_platforms: "/stats/opens/platforms", click_platforms: "/stats/clicks/platforms"
    }.each do |method, api_path|
      it "fetches #{method} from #{api_path}" do
        stub_api(:get, api_path, response: { "Days" => [{ "Date" => "2026-10-01", "WebMail" => 1 }] })
        expect(client.stats.public_send(method)).to eq(days: [{ date: "2026-10-01", web_mail: 1 }])
      end
    end

    it "keeps email client names verbatim" do
      stub_api(:get, "/stats/opens/emailclients", response: {
                 "Days" => [{ "Date" => "2026-10-01", "Apple Mail" => 17 }], "Apple Mail" => 17
               })
      expect(client.stats.email_clients).to eq(days: [{ date: "2026-10-01", counts: { "Apple Mail" => 17 } }],
                                               totals: { "Apple Mail" => 17 })
    end

    it "keeps browser family names verbatim" do
      stub_api(:get, "/stats/clicks/browserfamilies", response: { "Days" => [], "Yandex.Browser" => 3 })
      expect(client.stats.browser_families).to eq(days: [], totals: { "Yandex.Browser" => 3 })
    end

    it "rejects unknown filters" do
      expect { client.stats.overview(tag: "x") }.to raise_error(ArgumentError, /Unknown stats filter/)
    end
  end

  describe Haskimail::Resources::Webhooks do
    let(:webhook) do
      { "ID" => 905, "Url" => "https://example.com/hook", "MessageStream" => "2081",
        "Triggers" => { "Delivery" => { "Enabled" => true }, "SpamComplaint" => { "Enabled" => false } } }
    end

    it "lists and gets webhooks" do
      stub_api(:get, "/webhooks", response: { "Webhooks" => [webhook] })
      stub_api(:get, "/webhooks/905", response: webhook)
      expect(client.webhooks.list[:webhooks].first[:triggers]).to eq(delivery: { enabled: true },
                                                                     spam_complaint: { enabled: false })
      expect(client.webhooks.get(905)[:id]).to eq(905)
    end

    it "creates a webhook from shorthand triggers" do
      stub = stub_api(:post, "/webhooks", response: webhook, body: {
                        "Url" => "https://user:pass@example.com/hook", "MessageStream" => "2081",
                        "Triggers" => { "Delivery" => { "Enabled" => true }, "SpamComplaint" => { "Enabled" => false },
                                        "SubscriptionChange" => { "Enabled" => true } }
                      })
      client.webhooks.create(url: "https://user:pass@example.com/hook", message_stream: 2081,
                             triggers: { delivery: true, spam_complaint: { enabled: false },
                                         subscription_change: { "Enabled" => true } })
      expect(stub).to have_been_requested
    end

    it "updates only what is given" do
      stub = stub_api(:put, "/webhooks/905", response: webhook,
                                             body: { "Triggers" => { "Open" => { "Enabled" => true } } })
      client.webhooks.update(905, triggers: { open: true })
      expect(stub).to have_been_requested
    end

    it "deletes a webhook" do
      stub_api(:delete, "/webhooks/905", response: { "ErrorCode" => 0, "Message" => "Webhook 905 removed." })
      expect(client.webhooks.delete(905)[:error_code]).to eq(0)
    end

    it "validates input", :aggregate_failures do
      expect { client.webhooks.create(url: "javascript:alert(1)", triggers: { bounce: true }) }
        .to raise_error(ArgumentError, /http\(s\)/)
      expect { client.webhooks.create(url: "not a url", triggers: { bounce: true }) }
        .to raise_error(ArgumentError, /http\(s\)/)
      expect { client.webhooks.create(url: "https://e.com", triggers: {}) }.to raise_error(ArgumentError, /at least one/)
      expect { client.webhooks.create(url: "https://e.com", triggers: { bounse: true }) }
        .to raise_error(ArgumentError, /Unknown trigger/)
      expect { client.webhooks.create(url: "https://e.com", triggers: { bounce: "yes" }) }
        .to raise_error(ArgumentError, /true or false/)
      expect { client.webhooks.create(url: "https://e.com", triggers: [:bounce]) }
        .to raise_error(ArgumentError, /must be a Hash/)
      expect { client.webhooks.update(905) }.to raise_error(ArgumentError, /Nothing to update/)
      expect { client.webhooks.update(905, url: "ftp://e.com") }.to raise_error(ArgumentError)
    end
  end

  describe Haskimail::Resources::InboundRules do
    it "lists, iterates, creates and deletes rules" do
      stub_api(:get, "/triggers/inboundrules", query: { "count" => "100", "offset" => "0" },
                                               response: { "TotalCount" => 1, "InboundRules" => [{ "ID" => 3, "Rule" => "spam@example.com" }] })
      stub_api(:post, "/triggers/inboundrules", body: { "Rule" => "example.org" },
                                                response: { "ID" => 5, "Rule" => "example.org" })
      stub_api(:delete, "/triggers/inboundrules/5", response: { "ErrorCode" => 0, "Message" => "Rule 5 removed." })

      expect(client.inbound_rules.list[:inbound_rules]).to eq([{ id: 3, rule: "spam@example.com" }])
      expect(client.inbound_rules.each.to_a.size).to eq(1)
      expect(client.inbound_rules.create(" example.org ")).to eq(id: 5, rule: "example.org")
      expect(client.inbound_rules.delete(5)[:error_code]).to eq(0)
      expect { client.inbound_rules.create("") }.to raise_error(ArgumentError)
      expect { client.inbound_rules.list(count: 501) }.to raise_error(ArgumentError)
    end
  end

  describe Haskimail::Resources::Suppressions do
    it "dumps the list" do
      stub_api(:get, "/message-streams/2081/suppressions/dump", response: {
                 "Suppressions" => [{ "EmailAddress" => "a@b.ru", "SuppressionReason" => "HardBounce" }]
               })
      expect(client.suppressions.dump("2081")).to eq(suppressions: [{ email_address: "a@b.ru",
                                                                      suppression_reason: "HardBounce" }])
    end

    it "suppresses and unsuppresses addresses (deduplicated)" do
      body = { "Suppressions" => [{ "EmailAddress" => "a@b.ru" }, { "EmailAddress" => "c@d.ru" }] }
      add = stub_api(:post, "/message-streams/2081/suppressions", body: body, response: { "Suppressions" => [] })
      del = stub_api(:post, "/message-streams/2081/suppressions/delete", body: body, response: { "Suppressions" => [] })

      client.suppressions.suppress("2081", ["a@b.ru", " c@d.ru", "a@b.ru"])
      client.suppressions.unsuppress("2081", %w[a@b.ru c@d.ru])
      expect([add, del]).to all(have_been_requested)
      expect { client.suppressions.suppress("2081", [" "]) }.to raise_error(ArgumentError, /At least one/)
    end
  end
end
