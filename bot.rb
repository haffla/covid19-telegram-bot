# frozen_string_literal: true

require 'telegram/bot'
require_relative './covid_rki_stats'

def to_utf8(c)
  c.chr Encoding::UTF_8
end

FACE_WITH_MEDICAL_MASK = to_utf8(0x1F637)
FACE_WITH_HEAD_BANDAGE = to_utf8(0x1F915)
FACE_WITH_THERMOMETER = to_utf8(0x1F912)
FACES_SICK = [FACE_WITH_HEAD_BANDAGE, FACE_WITH_THERMOMETER].freeze

redis = Redis.new

Telegram::Bot::Client.run(ENV['TOKEN'], logger: Logger.new(STDOUT)) do |bot|
  bot.listen do |message|
    case message.text
    when '/start'
      bot.api.send_message(chat_id: message.chat.id, text: "Moin, #{message.from.first_name}. Go /inf")
    when '/inf'
      redis.incr 'called'
      bot.api.send_message(chat_id: message.chat.id, text: "Mom... #{FACE_WITH_MEDICAL_MASK}")
      stats, last_updated = CovidRkiStats.new(redis: redis).fetch
      bot.api.send_message(chat_id: message.chat.id, text: last_updated)
      text = stats.map do |state, inf, inf_inc, dead, dead_inc|
        [
          state,
          inf.to_s.ljust(5, ' '),
          format('%+d', inf_inc).to_s.ljust(3, ' '),
          dead.to_s.ljust(3, ' '),
          format('%+d', dead_inc).to_s.ljust(3, ' ')
        ].join(' | ')
      end.join("\n")

      pp text
      sleep 1
      bot.api.send_message(chat_id: message.chat.id, text: "```\n#{text}\n```", parse_mode: 'Markdown')
      if [true, false].sample
        sleep 2
        bot.api.send_message(chat_id: message.chat.id, text: FACES_SICK.sample)
      end
    end
  end
end
