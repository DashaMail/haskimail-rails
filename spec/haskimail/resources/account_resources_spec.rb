# frozen_string_literal: true

RSpec.describe "Account resources" do # rubocop:disable RSpec/DescribeClass
  let(:account) { account_client }
  let(:server) do
    { "ID" => 11_834, "Name" => "Интернет-магазин", "Color" => "purple", "TrackLinks" => "HtmlAndText",
      "DeliveryType" => "Live", "ApiTokens" => ["secret-token"], "InboundSpamThreshold" => 0 }
  end

  describe Haskimail::Resources::Servers do
    it "gets, lists and iterates servers with the account token" do
      stub_api(:get, "/servers/11834", token: :account, response: server)
      stub_api(:get, "/servers", token: :account, query: { "count" => "50", "offset" => "0" },
                                 response: { "TotalCount" => 1, "Servers" => [server] })

      expect(account.servers.get(11_834)).to include(id: 11_834, api_tokens: ["secret-token"])
      expect(account.servers.list[:total_count]).to eq(1)
      expect(account.servers.each.map { |s| s[:name] }).to eq(["Интернет-магазин"])
    end

    it "creates a server" do
      stub = stub_api(:post, "/servers", token: :account, response: server, body: {
                        "Name" => "Shop", "Color" => "blue", "SmtpApiActivated" => true, "TrackLinks" => "HtmlOnly",
                        "DeliveryType" => "Sandbox", "InboundSpamThreshold" => 15, "InboundHookUrl" => "https://e.com/in"
                      })
      account.servers.create(name: "Shop", color: "blue", smtp_api_activated: true, track_links: "HtmlOnly",
                             delivery_type: "Sandbox", inbound_spam_threshold: 15, inbound_hook_url: "https://e.com/in")
      expect(stub).to have_been_requested
    end

    it "updates a server partially" do
      stub = stub_api(:put, "/servers/11834", token: :account, response: server,
                                              body: { "TrackLinks" => false, "RawEmailEnabled" => true })
      account.servers.update(11_834, track_links: false, raw_email_enabled: true)
      expect(stub).to have_been_requested
    end

    it "issues an additional server token" do
      stub = stub_api(:post, "/servers/11834/tokens/new", token: :account,
                                                          body: { "Name" => "Интеграция 1С" },
                                                          response: { "Token" => "new-token", "ServerId" => 11_834 })
      expect(account.servers.issue_token(11_834, name: "Интеграция 1С")).to eq(token: "new-token",
                                                                               server_id: 11_834)
      expect(stub).to have_been_requested
    end

    it "issues a token without a name" do
      stub = stub_api(:post, "/servers/11834/tokens/new", token: :account, body: nil,
                                                          response: { "Token" => "new-token", "ServerId" => 11_834 })
      account.servers.issue_token(11_834)
      expect(stub).to have_been_requested
    end

    it "deletes a server" do
      stub_api(:delete, "/servers/11834", token: :account, response: { "ErrorCode" => 0, "Message" => "removed" })
      expect(account.servers.delete(11_834)[:error_code]).to eq(0)
    end

    it "validates attributes", :aggregate_failures do
      servers = account.servers
      expect { servers.create(name: "") }.to raise_error(ArgumentError, /name is required/)
      expect { servers.create(name: "x", color: "pink") }.to raise_error(ArgumentError, /color/)
      expect { servers.create(name: "x", track_links: "Always") }.to raise_error(ArgumentError, /track_links/)
      expect { servers.create(name: "x", delivery_type: "Test") }.to raise_error(ArgumentError, /delivery_type/)
      expect { servers.create(name: "x", inbound_spam_threshold: 7) }.to raise_error(ArgumentError, /steps of 5/)
      expect { servers.create(name: "x", inbound_spam_threshold: 35) }.to raise_error(ArgumentError, /steps of 5/)
      expect { servers.update(1, delivery_type: "Live") }.to raise_error(ArgumentError, /Unknown server attribute/)
      expect { servers.update(1) }.to raise_error(ArgumentError, /Nothing to update/)
    end

    it "explains a 401 when a server token is used for account endpoints" do
      stub_request(:get, "#{ApiHelpers::BASE_URL}/servers/1")
        .to_return(status: 401, body: '{"ErrorCode":10,"Message":"Invalid API key"}')
      expect { account.servers.get(1) }.to raise_error(Haskimail::UnauthorizedError) { |e|
        expect(e.code?(Haskimail::ErrorCodes::INVALID_API_TOKEN)).to be(true)
      }
    end
  end

  describe Haskimail::Resources::Domains do
    let(:domain) do
      { "ID" => 3127, "Name" => "example.com", "DKIMVerified" => true, "SPFVerified" => false,
        "SPFTextValue" => { "valid" => 0, "name" => "example.com.", "record_type" => "TXT", "value" => "v=spf1" } }
    end

    it "manages domains" do
      stub_api(:get, "/domains", token: :account, query: { "count" => "500", "offset" => "0" },
                                 response: { "TotalCount" => 1, "Domains" => [domain] })
      stub_api(:get, "/domains/3127", token: :account, response: domain)
      stub_api(:post, "/domains", token: :account, body: { "Name" => "example.com" }, response: domain)
      stub_api(:delete, "/domains/3127", token: :account, response: { "ErrorCode" => 0, "Message" => "removed" })
      stub_api(:put, "/domains/3127/verifyDkim", token: :account, response: { "DKIMVerified" => true })
      stub_api(:put, "/domains/3127/verifyspf", token: :account, response: { "SPFVerified" => true })

      expect(account.domains.list[:domains].first).to include(dkim_verified: true, spf_verified: false)
      expect(account.domains.each.to_a.size).to eq(1)
      expect(account.domains.get(3127)[:spf_text_value]).to include(record_type: "TXT", valid: 0)
      expect(account.domains.create(" example.com ")[:id]).to eq(3127)
      expect(account.domains.delete(3127)[:error_code]).to eq(0)
      expect(account.domains.verify_dkim(3127)).to eq(dkim_verified: true)
      expect(account.domains.verify_spf(3127)).to eq(spf_verified: true)
      expect { account.domains.create(nil) }.to raise_error(ArgumentError)
    end
  end

  describe Haskimail::Resources::AccountTemplates do
    it "previews and pushes templates between servers" do
      stub = stub_api(:put, "/templates/push", token: :account,
                                               body: { "SourceServerID" => 1, "DestinationServerID" => 2, "PerformChanges" => false },
                                               response: { "TotalCount" => 1, "Templates" => [{ "TemplateId" => 4521, "Name" => "A" }] })
      result = account.templates.push(source_server_id: 1, destination_server_id: 2, perform_changes: false)
      expect(result).to eq(total_count: 1, templates: [{ template_id: 4521, name: "A" }])
      expect(stub).to have_been_requested
    end

    it "requires an explicit perform_changes boolean and distinct servers", :aggregate_failures do
      expect { account.templates.push(source_server_id: 1, destination_server_id: 2, perform_changes: "yes") }
        .to raise_error(ArgumentError, /perform_changes/)
      expect { account.templates.push(source_server_id: 1, destination_server_id: 1, perform_changes: true) }
        .to raise_error(ArgumentError, /must differ/)
      expect { account.templates.push(source_server_id: nil, destination_server_id: 1, perform_changes: true) }
        .to raise_error(ArgumentError, /source_server_id/)
    end

    it "lists templates of all servers and validates with the account token" do
      stub_api(:get, "/templates", token: :account, query: { "count" => "500", "offset" => "0" },
                                   response: { "TotalCount" => 1, "Templates" => [{ "TemplateId" => 1, "Name" => "A" }] })
      stub_api(:post, "/templates/validate", token: :account, body: { "Subject" => "Hi" },
                                             response: { "AllContentIsValid" => true })
      expect(account.templates.list[:total_count]).to eq(1)
      expect(account.templates.each.map { |t| t[:name] }).to eq(["A"])
      expect(account.templates.validate(subject: "Hi")).to eq(all_content_is_valid: true)
    end

    it "creates a template on a given server" do
      stub = stub_api(:post, "/templates", token: :account,
                                           body: { "Name" => "N", "AssociatedServerId" => 11_834 }, response: { "TemplateId" => 1 })
      account.templates.create(associated_server_id: 11_834, name: "N")
      expect(stub).to have_been_requested
    end
  end
end
