# frozen_string_literal: true

def to_utf8(c)
  c.chr Encoding::UTF_8
end

module CovidBot
  COMMANDS = [
    ["rki", "Stats vom Robert Koch Institut (Deutschland)"],
    ["jhu", "Stats from John Hopkins University"],
    ["zeit", "Stats from zeit.de (Deutschland)"],
    ["sub", "Subscribe to source updates"],
    ["unsub", "Unsubscribe from source updates"],
    ["pref", "Edit preferences"]
  ].freeze

  FACE_WITH_MEDICAL_MASK = to_utf8(0x1F637)
  FACE_WITH_THERMOMETER = to_utf8(0x1F912)
  FACE_NAUSEATED = to_utf8(0x1F922)
  FACE_ROBOT = to_utf8(0x1F916)
end
