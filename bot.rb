# frozen_string_literal: true

require 'telegram/bot'
require_relative './covid_stats'

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
      redis.incr "called"
      bot.api.send_message(chat_id: message.chat.id, text: "Mom... #{FACE_WITH_MEDICAL_MASK}")
      stats = CovidStats.new(redis: redis).fetch
      just = stats.inject(0) { |current, (_k, v)| current > v[:current].to_s.size ? current : v[:current].to_s.size }
      tl, be, nk, kb, pa = stats.values_at(:total, :berlin, :nk, :kb, :pan)
      sleep 1
      text = <<~MD
        ```
        Schland    | #{tl[:current].to_s.ljust(just, ' ')} | #{tl[:previous]} (#{tl[:increase]}%)
        Berlin     | #{be[:current].to_s.ljust(just, ' ')} | #{be[:previous]} (#{be[:increase]}%)
        Neukölln   | #{nk[:current].to_s.ljust(just, ' ')} | #{nk[:previous]} (#{nk[:increase]}%)
        Kreuzberg  | #{kb[:current].to_s.ljust(just, ' ')} | #{kb[:previous]} (#{kb[:increase]}%)
        Pankow     | #{pa[:current].to_s.ljust(just, ' ')} | #{pa[:previous]} (#{pa[:increase]}%)
        ```
      MD
      bot.api.send_message(chat_id: message.chat.id, text: text, parse_mode: 'Markdown')
      if [true, false].sample
        sleep 2
        bot.api.send_message(chat_id: message.chat.id, text: FACES_SICK.sample)
      end
    end
  end
end
