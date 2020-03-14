# frozen_string_literal: true

require "telegram/bot"
require "raven"
require "concurrent"
require_relative "./covid_rki_stats"
require_relative "./md_table"

Raven.configure do |config|
  config.dsn = ENV["SENTRY_DSN"]
end

def to_utf8(c)
  c.chr Encoding::UTF_8
end

class Bot
  attr_reader :redis

  FACE_WITH_MEDICAL_MASK = to_utf8(0x1F637)
  FACE_WITH_HEAD_BANDAGE = to_utf8(0x1F915)
  FACE_WITH_THERMOMETER = to_utf8(0x1F912)
  FACE_ROBOT = to_utf8(0x1F916)
  FACES_SICK = [FACE_WITH_HEAD_BANDAGE, FACE_WITH_THERMOMETER].freeze

  class Checker
    attr_reader :redis, :bot

    def initialize(redis:, bot:)
      @redis = redis
      @bot = bot
    end

    def start_polling
      task = Concurrent::TimerTask
        .new(execution_interval: 600, run_now: true) { poll }

      task.execute
    end

    def poll
      last_updated = CovidRkiStats
        .new(redis: redis)
        .fetch(last_updated_only: true)

      redis.get("rki_last_updated_at").then do |r|
        if r != last_updated
          redis.set("rki_last_updated_at", last_updated)
          unless r.nil?
            redis.del("RKI_BODY")
            clients = redis.smembers("clients") || []
            clients.each do |client|
              bot.api.send_message(
                chat_id: client,
                text: "#{FACE_ROBOT} Das RKI hat neue Zahlen: /inf order /trend",
                parse_mode: "Markdown"
              )
            end
          end
        end
      end
    end
  end

  def initialize
    @redis = Redis.new
  end

  def run!
    Telegram::Bot::Client.run(ENV["TOKEN"], logger: Logger.new(STDOUT)) do |bot|
      checker = Checker.new(redis: redis, bot: bot)
      checker.start_polling

      bot.listen do |message|
        redis.sadd "clients", message.chat.id
        case message.text
        when "/start"
          redis.incr "installed"
          bot.api.send_message(
            chat_id: message.chat.id,
            text: "Moin, #{message.from.first_name}. Versuch mal /inf oder /trend."
          )
        when "/inf", "/trend"
          show_trend = message.text == "/trend"
          redis.incr "called"

          bot.api.send_message(
            chat_id: message.chat.id,
            text: "Robert Koch sagt... #{FACE_WITH_MEDICAL_MASK}"
          )

          sleep 0.5
          stats, last_updated = CovidRkiStats.new(redis: redis).fetch

          bot.api.send_message(
            chat_id: message.chat.id,
            text: "*#{last_updated}*",
            parse_mode: "Markdown"
          )

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
        end
      end
    end
  end
end

Raven.capture { Bot.new.run! }

