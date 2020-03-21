# frozen_string_literal: true

require "rubygems"
require "bundler/setup"

Bundler.require(:default)

loader = Zeitwerk::Loader.new
loader.push_dir("lib")
loader.setup
loader.eager_load if ENV["BOT_ENV"] == "production"

$stdout.sync = true

Raven.configure do |config|
  config.dsn = ENV["SENTRY_DSN"]
end

Raven.capture do
  CovidBot::Bot.new.run!
end
