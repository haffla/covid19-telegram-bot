# frozen_string_literal: true

module CovidBot
  class Bot
    include Logging

    attr_reader :redis

    def initialize
      @redis = Redis.new
    end

    def run!
      Telegram::Bot::Client.run(ENV["TOKEN"], logger: logger) do |bot|
        poller = Poller.new(redis: redis, bot: bot)
        poller.start

        bot.listen do |message|
          case message
          when Telegram::Bot::Types::CallbackQuery
            id = message.message.chat.id
            case message.data
            when "sub_rki"
              redis.sadd "clients", id
              bot.api.send_message(chat_id: id, text: "Don't sweat it. You're subscribed to updates from RKI. /unsub if you change your mind.")
            when "sub_zeit"
              redis.sadd "zeit_clients", id
              bot.api.send_message(chat_id: id, text: "Die Zeit heilt alle Wunden. /unsub in case you want to stop receiving updates.")
            when "sub_jhu"
              redis.sadd "jhu_clients", id
              bot.api.send_message(chat_id: id, text: "Johns Hopkins won't let you down!")
            when "unsub_rki"
              redis.srem "clients", id
              bot.api.send_message(chat_id: id, text: "I hate to see you go... RKI will not bother you anymore.")
            when "unsub_zeit"
              redis.srem "zeit_clients", id
              bot.api.send_message(chat_id: id, text: "Die Zeit vergeht. You will not receive any more updates. Ciao!")
            when "unsub_jhu"
              redis.srem "jhu_clients", id
              bot.api.send_message(chat_id: id, text: "John Hopkins won't bother you anymore!")
            else
              raise StandardError, "Unknown callback_query #{message.data}"
            end
          when Telegram::Bot::Types::Message
            case message.text
            when nil # apparently this is what happens when a bot is added/removed to a group chat
              if message.left_chat_member
                redis.srem("clients", message.chat.id)
                redis.srem("zeit_clients", message.chat.id)
                redis.srem("jhu_clients", message.chat.id)
              elsif message.new_chat_members && !message.new_chat_members.empty?
                bot.api.send_message(chat_id: message.chat.id, text: "Hi I'm Covid Watch!")
                bot.api.send_message(
                  chat_id: message.chat.id,
                  text: COMMANDS.map { |c| "/#{c[0]} - #{c[1]}" }.join("\n")
                )
              end
            when %r{^/start}
              redis.incr "installed"
              bot.api.send_message(
                chat_id: message.chat.id,
                text: "Moin, #{message.from.first_name}. Versuch mal /rki oder /zeit."
              )

              bot.api.send_message(
                chat_id: message.chat.id,
                text: "/jhu for international stats."
              )

              redis.sadd("clients", message.chat.id)
              redis.sadd("zeit_clients", message.chat.id)

              bot.api.send_message(
                chat_id: message.chat.id,
                text: "Oh and... I subscribed you to updates of RKI. So whenever they update their data I will let you know. /unsub if you don't want that."
              )
            when %r{^/jhu}
              async :handle_jhu, bot, message, "Johns Hopkins"
            when %r{^/rki}
              async :handle_rki, bot, message, "RKI"
            when %r{^/zeit}
              async :handle_zeit, bot, message, "Die Zeit"
            when %r{^/sub}
              kb = [
                Telegram::Bot::Types::InlineKeyboardButton.new(text: "Robert Koch", callback_data: "sub_rki"),
                Telegram::Bot::Types::InlineKeyboardButton.new(text: "Die Zeit", callback_data: "sub_zeit"),
                Telegram::Bot::Types::InlineKeyboardButton.new(text: "Johns Hopkins", callback_data: "sub_jhu")
              ]
              markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
              bot.api.send_message(chat_id: message.chat.id, text: "Which stats do you want to get updates for?", reply_markup: markup)
            when %r{^/unsub}
              kb = [
                Telegram::Bot::Types::InlineKeyboardButton.new(text: "Robert Koch", callback_data: "unsub_rki"),
                Telegram::Bot::Types::InlineKeyboardButton.new(text: "Die Zeit", callback_data: "unsub_zeit"),
                Telegram::Bot::Types::InlineKeyboardButton.new(text: "Johns Hopkins", callback_data: "unsub_jhu")
              ]
              markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
              bot.api.send_message(chat_id: message.chat.id, text: "Alright. Which source do you want to stop receiving updates from?", reply_markup: markup)
            when %r{^/pref}
              bot.api.send_message(chat_id: message.chat.id, text: "Sorry, nothing here... yet")
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

              text = message.text.gsub("_", "-")
              text = if text.size > 20
                       text[0..20] + "..."
                     else
                       text
                     end

              bot.api.send_message(
                chat_id: message.chat.id,
                text: "_#{text}_\n\nNo hablo eso!",
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

    private

    def async(meth, bot, message, source)
      Thread.new do
        time = Time.now.to_f
        Raven.capture do
          bot.api.send_chat_action(
            chat_id: message.chat.id,
            action: "typing"
          )
          sleep 1
          send meth, bot, message
          logger.debug "Took #{(Time.now.to_f - time).round(2)} seconds"
        rescue StandardError => e
          bot.api.send_message(
            chat_id: message.chat.id,
            text: "*🤖 Fatal!\nI'm having trouble fetching data from #{source}. Please try again later.*",
            parse_mode: "Markdown"
          )
          raise e
        end
      end
    end

    def handle_jhu(bot, message)
      track(message.from, :jhu)

      data, last_updated = Source::JohnsHopkins.new(redis: redis).fetch
      labels = %w[Country Confirmed Deaths]
      bot.api.send_message(
        chat_id: message.chat.id,
        text: "*Last updated at #{last_updated} \n#{labels.join(' | ')}\nIn parentheses: Compared to previous day*",
        parse_mode: "Markdown"
      )

      data.map! do |country, con, con_inc, deaths, deaths_inc|
        [
          country,
          "#{display(con)} (#{display(con_inc, prefix: true)})",
          "#{display(deaths)} (#{display(deaths_inc, prefix: true)})"
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
    end

    def handle_zeit(bot, message)
      track(message.from, :zeit)

      data, last_updated = Source::DieZeit.new(redis: redis).fetch
      data.map! do |country, con, deaths, active|
        [
          country,
          display(con).to_s,
          display(deaths).to_s,
          display(active).to_s
        ]
      end

      labels = ["Land", "Infizierte Total", "Todesfälle", "Derzeit Infizierte"]
      bot.api.send_message(
        chat_id: message.chat.id,
        text: "*#{last_updated}\n#{labels.join(' | ')}*",
        parse_mode: "Markdown"
      )

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

      unless redis.sismember("zeit_clients", message.chat.id)
        bot.api.send_message(
          chat_id: message.chat.id,
          text: "/sub um Notifications zu erhalten"
        )
      end
    end

    def handle_rki(bot, message)
      track(message.from, :rki)

      stats, last_updated = Source::Rki.new(redis: redis).fetch

      percentage_explanation = "\nIn Klammern: Vergleich zum Vortag"
      bot.api.send_message(
        chat_id: message.chat.id,
        text: "*#{last_updated}\nLand | Infizierte | 7-Tage-Inzidenz#{percentage_explanation}*",
        parse_mode: "Markdown"
      )

      data = stats.map do |state, inf, inf_inc, seven_day_i|
        [
          state,
          "#{display(inf)} (#{display(inf_inc, prefix: true)})",
          display(seven_day_i).to_s
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

      is_subscribed = redis.sismember "clients", message.chat.id
      unless is_subscribed
        bot.api.send_message(
          chat_id: message.chat.id,
          text: "/sub um Notifications zu erhalten"
        )
      end
    end

    def display(val, prefix: false)
      return "-" if val.nil?

      sign = if val.nil? || val.zero? || val.negative?
               ""
             else
               "+"
             end
      formatted = val >= 9_999 ? SI.convert(val) : val
      prefix ? sign + formatted.to_s : formatted
    end

    def track(from, source)
      data = { f: from.first_name, l: from.last_name, u: from.username, last: Time.now.to_s }
      redis.hset "users", from.id, data.to_json
      redis.incr "called_#{source}"
    end
  end
end
