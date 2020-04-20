# frozen_string_literal: true

require "./environment"

Raven.configure do |config|
  config.dsn = ENV["SENTRY_DSN"]
end

Raven.capture do
  CovidBot::Bot.new.run!
end
