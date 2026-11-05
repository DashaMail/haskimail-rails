# frozen_string_literal: true

require "rails"
require "action_mailer/railtie"
require "haskimail/rails/railtie"
require "rails/generators"
require "tmpdir"

RSpec.describe Haskimail::Rails::Railtie do
  let(:initializer) { described_class.initializers.find { |i| i.name == "haskimail.configure" } }

  def app_with(settings)
    config = ActiveSupport::OrderedOptions.new
    config.haskimail = ActiveSupport::OrderedOptions.new.merge!(settings)
    instance_double(Rails::Application, config: config)
  end

  it "exposes config.haskimail" do
    expect(described_class.config.haskimail).to be_a(ActiveSupport::OrderedOptions)
  end

  it "applies config.haskimail to the global configuration" do
    initializer.run(app_with(server_token: "from-rails-config", default_message_stream: "2081"))
    expect(Haskimail.config.server_token).to eq("from-rails-config")
    expect(Haskimail.config.default_message_stream).to eq("2081")
  end

  it "rejects unknown options" do
    expect { initializer.run(app_with(sever_token: "typo")) }
      .to raise_error(Haskimail::ConfigurationError, /sever_token/)
  end

  it "loads the install generator" do
    described_class.instance.send(:run_generators_blocks, Rails.application || Class.new(Rails::Application))
    expect(defined?(Haskimail::Generators::InstallGenerator)).to eq("constant")
  end

  describe "install generator" do
    it "creates the initializer" do
      require "generators/haskimail/install/install_generator"
      Dir.mktmpdir do |dir|
        generator = Haskimail::Generators::InstallGenerator.new([], { quiet: true }, destination_root: dir)
        allow(generator).to receive(:say)
        generator.invoke_all
        content = File.read(File.join(dir, "config/initializers/haskimail.rb"))
        expect(content).to include("Haskimail.configure", "credentials.haskimail")
        expect { RubyVM::InstructionSequence.compile(content) }.not_to raise_error
      end
    end
  end
end
