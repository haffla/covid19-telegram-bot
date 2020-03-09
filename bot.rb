require "telegram/bot"
require_relative "./covid_stats"

def to_utf8(c)
  c.chr Encoding::UTF_8
end

FACE_WITH_MEDICAL_MASK = to_utf8(0x1F637)
FACE_WITH_HEAD_BANDAGE = to_utf8(0x1F915)
FACE_WITH_THERMOMETER = to_utf8(0x1F912)
FACES_SICK = [FACE_WITH_HEAD_BANDAGE, FACE_WITH_THERMOMETER]

Telegram::Bot::Client.run(ENV["TOKEN"], logger: Logger.new(STDOUT)) do |bot|
  bot.listen do |message|
    case message.text
    when "/start"
      bot.api.send_message(chat_id: message.chat.id, text: "Moin, #{message.from.first_name}. Go /covid")
    when "/covid"
      bot.api.send_message(chat_id: message.chat.id, text: "Mom... #{FACE_WITH_MEDICAL_MASK}")
      total, berlin, nk, kb, pan = CovidStats.fetch
      sleep 1
      text = <<~MD
      ```
       Schland   | #{total}
       Berlin    | #{berlin}
       Neukölln  | #{nk}
       Kreuzberg | #{kb}
       Pankow    | #{pan}
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
