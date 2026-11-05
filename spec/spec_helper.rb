# frozen_string_literal: true

require "logger" # Rails 6.1 relies on Logger being loaded already
require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
  minimum_coverage line: 98, branch: 90
end

require "webmock/rspec"
require "action_mailer"
require "haskimail-rails"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |file| require file }

WebMock.disable_net_connect!

RSpec::Matchers.define_negated_matcher :exclude, :include

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = ".rspec_status"

  config.include ApiHelpers

  config.before do
    Haskimail.reset_config!
    Thread.current[Haskimail::Connection::THREAD_KEY] = nil
    # Never actually sleep between retries in tests.
    allow_any_instance_of(Haskimail::Connection).to receive(:pause) # rubocop:disable RSpec/AnyInstance
  end
end
