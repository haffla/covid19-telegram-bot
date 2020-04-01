# frozen_string_literal: true

module CovidBot
  COMMANDS = [
    ["rki", "Stats vom Robert Koch Institut (Deutschland)"],
    ["jhu", "Stats from John Hopkins University"],
    ["zeit", "Stats from zeit.de (Deutschland)"],
    ["sub", "Subscribe to source updates"],
    ["unsub", "Unsubscribe from source updates"],
    ["pref", "Edit preferences"]
  ].freeze
end
