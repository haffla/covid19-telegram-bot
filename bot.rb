# frozen_string_literal: true

require "telegram/bot"
require "raven"
require "concurrent"
require "ruby_cowsay"
require_relative "./covid_rki_stats"
require_relative "./john_hopkins_stats"
require_relative "./zeit_stats"
require_relative "./md_table"
require_relative "./poller"

Raven.configure do |config|
  config.dsn = ENV["SENTRY_DSN"]
end

def to_utf8(c)
  c.chr Encoding::UTF_8
end

def percent(val)
  val.zero? ? "-" : "#{format('%+d', val)}%"
end

COMMANDS = [
  ["rki", "Stats vom Robert Koch Institut (Deutschland)"],
  ["jhu", "Stats from John Hopkins University"],
  ["zeit", "Stats from zeit.de"]
].freeze

class Bot
  attr_reader :redis

  FACE_WITH_MEDICAL_MASK = to_utf8(0x1F637)
  FACE_WITH_HEAD_BANDAGE = to_utf8(0x1F915)
  FACE_WITH_THERMOMETER = to_utf8(0x1F912)
  FACE_NAUSEATED = to_utf8(0x1F922)
  FACE_ROBOT = to_utf8(0x1F916)
  THUMBS_UP = to_utf8(0x1F44D)
  FACE_SKULL = to_utf8(0x1F480)
  FACES_SICK = [FACE_WITH_HEAD_BANDAGE, FACE_WITH_THERMOMETER].freeze

  def initialize
    @redis = Redis.new
  end

  def run!
    Telegram::Bot::Client.run(ENV["TOKEN"], logger: Logger.new(STDOUT)) do |bot|
      poller = Poller.new(redis: redis, bot: bot)
      poller.start

      bot.listen do |message|
        case message
        when Telegram::Bot::Types::CallbackQuery
          case message.data
          when "sub_rki"
            redis.sadd "clients", message.from.id
            bot.api.send_message(chat_id: message.from.id, text: "Don't sweat it. You're subscribed to updates from RKI. /unsub if you change your mind.")
          when "sub_zeit"
            redis.sadd "zeit_clients", message.from.id
            bot.api.send_message(chat_id: message.from.id, text: "Die Zeit heilt alle Wunden. /unsub in case you want to stop receiving updates.")
          when "unsub_rki"
            redis.srem "clients", message.from.id
            bot.api.send_message(chat_id: message.from.id, text: "I hate to see you go... RKI will not bother you anymore.")
          when "unsub_zeit"
            redis.srem "zeit_clients", message.from.id
            bot.api.send_message(chat_id: message.from.id, text: "Die Zeit vergeht. You will not receive any updates anymore. Ciao!")
          end
        else
          case message.text
          when %r{^/start}
            redis.incr "installed"
            bot.api.send_message(
              chat_id: message.chat.id,
              text: "Moin, #{message.from.first_name}. Versuch mal /rki oder /zeit."
            )

            sleep 1

            bot.api.send_message(
              chat_id: message.chat.id,
              text: "/jhu for international stats."
            )

            sleep 1

            redis.sadd("clients", message.chat.id)
            redis.sadd("zeit_clients", message.chat.id)

            bot.api.send_message(
              chat_id: message.chat.id,
              text: "Oh and... I subscribed you to updates of RKI and Die Zeit. So whenever they update their data I will let you know. /unsub if you don't want that."
            )
          when %r{^/jhu}
            redis.incr "called"
            bot.api.send_message(
              chat_id: message.chat.id,
              text: "John Hopkins says... #{FACE_NAUSEATED}"
            )

            sleep 0.5
            data, last_updated = JohnHopkinsStats.new(redis: redis).fetch

            bot.api.send_message(
              chat_id: message.chat.id,
              text: "*Last updated at #{last_updated} \nCountry | Confirmed | Deaths | Recovered\nPercentage: Compared to previous day*",
              parse_mode: "Markdown"
            )

            data.map! do |country, con, con_inc, deaths, deaths_inc, rec, rec_inc|
              [
                country,
                "#{con} #{percent(con_inc)}",
                "#{deaths} #{percent(deaths_inc)}",
                "#{rec} #{percent(rec_inc)}"
              ]
            end

            sleep 0.7
            text = <<~MD
              ```
              #{MdTable.make(data: data)}
              ```
            MD

            bot.api.send_message(
              chat_id: message.chat.id,
              text: text,
              parse_mode: "Markdown"
            )
          when %r{^/rki}
            from = message.from
            data = { f: from.first_name, l: from.last_name, u: from.username }
            redis.hset "users", from.id, data.to_json

            redis.incr "called"

            bot.api.send_message(
              chat_id: message.chat.id,
              text: "Robert Koch sagt... #{FACE_WITH_MEDICAL_MASK}"
            )

            sleep 0.5
            stats, last_updated = CovidRkiStats.new(redis: redis).fetch

            percentage_explanation = "\nProzente: Vergleich zum Vortag"
            bot.api.send_message(
              chat_id: message.chat.id,
              text: "*#{last_updated}\nLand | Infizierte | Todesfälle#{percentage_explanation}*",
              parse_mode: "Markdown"
            )

            data = stats.map do |state, inf, inf_inc, dead, dead_inc|
              [
                state,
                "#{inf} #{percent(inf_inc)}",
                "#{dead} #{percent(dead_inc)}"
              ].compact
            end

            text = <<~MD
              ```
              #{MdTable.make(data: data)}
              ```
            MD

            bot.api.send_message(
              chat_id: message.chat.id,
              text: text,
              parse_mode: "Markdown"
            )

            if [true, false].sample
              sleep 2
              bot.api.send_message(
                chat_id: message.chat.id,
                text: FACES_SICK.sample
              )
            end
          when %r{/zeit}
            redis.incr "called"
            bot.api.send_message(
              chat_id: message.chat.id,
              text: "Die Zeit sagt... #{FACE_WITH_MEDICAL_MASK}"
            )

            data, last_updated = ZeitStats.new.fetch

            bot.api.send_message(
              chat_id: message.chat.id,
              text: "*#{last_updated}\nLand | Infizierte | Todesfälle | Genesene*",
              parse_mode: "Markdown"
            )

            sleep 0.7

            text = <<~MD
              ```
              #{MdTable.make(data: data)}
              ```
            MD

            bot.api.send_message(
              chat_id: message.chat.id,
              text: text,
              parse_mode: "Markdown"
            )
          when %r{/sub}
            kb = [
              Telegram::Bot::Types::InlineKeyboardButton.new(text: "Robert Koch", callback_data: "sub_rki"),
              Telegram::Bot::Types::InlineKeyboardButton.new(text: "Die Zeit", callback_data: "sub_zeit")
            ]
            markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
            bot.api.send_message(chat_id: message.chat.id, text: "Which stats do you want to get updates for?", reply_markup: markup)
          when %r{/unsub}
            kb = [
              Telegram::Bot::Types::InlineKeyboardButton.new(text: "Robert Koch", callback_data: "unsub_rki"),
              Telegram::Bot::Types::InlineKeyboardButton.new(text: "Die Zeit", callback_data: "unsub_zeit")
            ]
            markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
            bot.api.send_message(chat_id: message.chat.id, text: "Alright. Which source do you want to stop receiving updates from?", reply_markup: markup)
          else
            text = <<~MD
              ```
              #{Cow.new(face_type: 'paranoid').say('Wuut?')}
              ```
            MD

            bot.api.send_message(
              chat_id: message.chat.id,
              text: text,
              parse_mode: "Markdown"
            )

            sleep 0.7

            text = message.text.gsub("_", "-")
            text = if text.size > 20
                     text[0..20] + "..."
                   else
                     text
                   end

            bot.api.send_message(
              chat_id: message.chat.id,
              text: "_#{message}_\n\nNo hablo eso!",
              parse_mode: "Markdown"
            )

            bot.api.send_message(
              chat_id: message.chat.id,
              text: COMMANDS.map { |c| "/#{c[0]} - #{c[1]}" }.join("\n")
            )
          end
        end
      end
    end
  end
end

Raven.capture { Bot.new.run! }
