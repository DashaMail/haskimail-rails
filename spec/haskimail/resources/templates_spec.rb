# frozen_string_literal: true

RSpec.describe Haskimail::Resources::Templates do
  let(:templates) { server_client.templates }
  let(:template) do
    { "TemplateId" => 4521, "Name" => "Заказ оформлен", "Subject" => "Заказ №{{order}}",
      "HtmlBody" => "<p>{{name}}</p>", "TextBody" => "{{name}}", "AssociatedServerId" => 11_834 }
  end

  it "gets a template by id" do
    stub_api(:get, "/templates/4521", response: template)
    expect(templates.get(4521)).to include(template_id: 4521, associated_server_id: 11_834)
  end

  it "URL-encodes aliases so they cannot alter the path", :aggregate_failures do
    stub = stub_api(:get, "/templates/%D0%B7%D0%B0%D0%BA%D0%B0%D0%B7%2F..%3Fx%3D1", response: template)
    templates.get("заказ/..?x=1")
    expect(stub).to have_been_requested
    expect { templates.get("..") }.to raise_error(ArgumentError, /Invalid path parameter/)
    expect { templates.get(" ") }.to raise_error(ArgumentError, /blank/)
  end

  it "lists with pagination" do
    stub_api(:get, "/templates", query: { "count" => "100", "offset" => "5" },
                                 response: { "TotalCount" => 2, "Templates" => [{ "TemplateId" => 1, "Name" => "A" }] })
    expect(templates.list(count: 100, offset: 5)).to eq(total_count: 2, templates: [{ template_id: 1, name: "A" }])
  end

  it "validates pagination arguments", :aggregate_failures do
    expect { templates.list(count: 0) }.to raise_error(ArgumentError, /count/)
    expect { templates.list(offset: -1) }.to raise_error(ArgumentError, /offset/)
    expect { templates.list(count: "10") }.to raise_error(ArgumentError, /Integer/)
  end

  it "iterates over all pages lazily" do
    stub_api(:get, "/templates", query: { "count" => "2", "offset" => "0" },
                                 response: { "TotalCount" => 3, "Templates" => [{ "TemplateId" => 1 }, { "TemplateId" => 2 }] })
    stub_api(:get, "/templates", query: { "count" => "2", "offset" => "2" },
                                 response: { "TotalCount" => 3, "Templates" => [{ "TemplateId" => 3 }] })

    expect(templates.each(page_size: 2).map { |t| t[:template_id] }).to eq([1, 2, 3])
    seen = []
    templates.each(page_size: 2) { |t| seen << t[:template_id] }
    expect(seen).to eq([1, 2, 3])
  end

  it "creates a template" do
    stub = stub_api(:post, "/templates", response: { "TemplateId" => 1, "Name" => "N" },
                                         body: { "Name" => "N", "Subject" => "S", "HtmlBody" => "<p/>" })
    expect(templates.create(name: "N", subject: "S", html_body: "<p/>")).to eq(template_id: 1, name: "N")
    expect(stub).to have_been_requested
    expect { templates.create(name: "") }.to raise_error(ArgumentError, /name is required/)
  end

  it "updates every field (the API overwrites the template)" do
    stub = stub_api(:put, "/templates/4521", response: { "TemplateId" => 4521, "Name" => "N" },
                                             body: { "Name" => "N", "Subject" => "", "HtmlBody" => "h", "TextBody" => "" })
    templates.update(4521, name: "N", subject: nil, html_body: "h", text_body: nil)
    expect(stub).to have_been_requested
  end

  it "patches a single field while preserving the others" do
    stub_api(:get, "/templates/4521", response: template)
    stub = stub_api(:put, "/templates/4521", response: { "TemplateId" => 4521 }, body: {
                      "Name" => "Заказ оформлен", "Subject" => "Новая тема",
                      "HtmlBody" => "<p>{{name}}</p>", "TextBody" => "{{name}}"
                    })
    templates.patch(4521, subject: "Новая тема")
    expect(stub).to have_been_requested
    expect { templates.patch(1, color: "x") }.to raise_error(ArgumentError, /Unknown template/)
  end

  it "deletes a template" do
    stub_api(:delete, "/templates/welcome", response: { "ErrorCode" => 0, "Message" => "Template removed." })
    expect(templates.delete("welcome")).to eq(error_code: 0, message: "Template removed.")
  end

  it "validates a template, keeping placeholder keys verbatim" do
    stub_api(:post, "/templates/validate",
             body: { "Subject" => "{{order}}", "TestRenderModel" => { "{{order}}" => "1042" } },
             response: {
               "AllContentIsValid" => true,
               "Subject" => { "ContentIsValid" => true, "ValidationErrors" => [], "RenderedContent" => "1042" },
               "SuggestedTemplateModel" => { "{{order}}" => "1042" }
             })
    result = templates.validate(subject: "{{order}}", test_render_model: { "{{order}}" => "1042" })
    expect(result).to eq(all_content_is_valid: true,
                         subject: { content_is_valid: true, validation_errors: [], rendered_content: "1042" },
                         suggested_template_model: { "{{order}}" => "1042" })
    expect { templates.validate }.to raise_error(ArgumentError, /At least one/)
  end
end
