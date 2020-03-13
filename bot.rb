# frozen_string_literal: true

require "telegram/bot"
require_relative "./covid_rki_stats"
require_relative "./md_table"

def to_utf8(c)
  c.chr Encoding::UTF_8
end

FACE_WITH_MEDICAL_MASK = to_utf8(0x1F637)
FACE_WITH_HEAD_BANDAGE = to_utf8(0x1F915)
FACE_WITH_THERMOMETER = to_utf8(0x1F912)
FACES_SICK = [FACE_WITH_HEAD_BANDAGE, FACE_WITH_THERMOMETER].freeze

redis = Redis.new

Telegram::Bot::Client.run(ENV["TOKEN"], logger: Logger.new(STDOUT)) do |bot|
  bot.listen do |message|
    case message.text
    when "/start"
      bot.api.send_message(chat_id: message.chat.id, text: "Moin, #{message.from.first_name}. Go /inf")
    when "/inf", "/trend"
      show_trend = message.text == "/trend"
      redis.incr "called"
      bot.api.send_message(chat_id: message.chat.id, text: "Mom... #{FACE_WITH_MEDICAL_MASK}")
      sleep 1
      stats, last_updated = CovidRkiStats.new(redis: redis).fetch
      bot.api.send_message(chat_id: message.chat.id, text: last_updated)

      data = stats.map do |state, inf, inf_inc, dead, dead_inc|
        [
          state,
          inf,
          ("#{format('%+d', inf_inc)}%" if show_trend),
          dead,
          ("#{format('%+d', dead_inc)}%" if show_trend)
        ].compact
      end

      text = <<~MD
        ```
        #{MdTable.make(data: data)}
        ```
      MD
      bot.api.send_message(chat_id: message.chat.id, text: text, parse_mode: "Markdown")
      if [true, false].sample
        sleep 2
        bot.api.send_message(chat_id: message.chat.id, text: FACES_SICK.sample)
      end
    end
  end
end
