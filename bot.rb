require "telegram/bot"
require_relative "./covid_stats"

Telegram::Bot::Client.run(ENV["TOKEN"], logger: Logger.new(STDOUT)) do |bot|
  bot.listen do |message|
    case message.text
    when "/start"
      bot.api.send_message(chat_id: message.chat.id, text: "Hello, #{message.from.first_name}. Type /covid")
    when "/covid"
      total, berlin = CovidStats.fetch
      bot.api.send_message(chat_id: message.chat.id, text: "Deutschland: #{total}\r\nBerlin: #{berlin}")
    end
  end
end
