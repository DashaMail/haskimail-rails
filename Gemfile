# frozen_string_literal: true

source "https://rubygems.org"

gemspec

rails_version = ENV.fetch("RAILS_VERSION", ">= 6.1")
gem "actionmailer", rails_version
# Older ActiveSupport releases pass options that json 3.x no longer accepts.
gem "json", "< 3" if rails_version.match?(/\A~> (6\.|7\.|8\.0)/)
# Rails < 7.1 does not require Logger itself on newer Rubies.
gem "concurrent-ruby", "< 1.3.5" if rails_version.match?(/\A~> (6\.|7\.0)/)
gem "railties", rails_version
gem "rake", "~> 13.0"
gem "rspec", "~> 3.13"
gem "rubocop", "~> 1.66", require: false
gem "rubocop-rake", "~> 0.6", require: false
gem "rubocop-rspec", "~> 3.0", require: false
gem "simplecov", "~> 0.22", require: false
gem "webmock", "~> 3.23"
