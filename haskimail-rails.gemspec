# frozen_string_literal: true

require_relative "lib/haskimail/version"

Gem::Specification.new do |spec|
  spec.name = "haskimail-rails"
  spec.version = Haskimail::VERSION
  spec.authors = ["DashaMail"]
  spec.email = ["support@haskimail.ru"]

  spec.summary = "Ruby on Rails SDK for the Haskimail transactional email API"
  spec.description = <<~DESC.tr("\n", " ").strip
    Ruby client and Rails integration for Haskimail
    (https://haskimail.ru): ActionMailer delivery method, full HTTP API coverage
    (email, templates, messages, bounces, servers, message streams, domains, stats,
    webhooks, inbound rules, suppressions), safe retries and webhook verification.
  DESC
  spec.homepage = "https://haskimail.ru/developer"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actionmailer", ">= 6.1", "< 9"
  spec.add_dependency "base64", ">= 0.1", "< 1"
end
