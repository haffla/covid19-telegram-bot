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
            when "unsub_rki"
              redis.srem "clients", id
              bot.api.send_message(chat_id: id, text: "I hate to see you go... RKI will not bother you anymore.")
            when "unsub_zeit"
              redis.srem "zeit_clients", id
              bot.api.send_message(chat_id: id, text: "Die Zeit vergeht. You will not receive any more updates. Ciao!")
            when "disable_recovered"
              settings = redis.hget("settings", id).then { |h| h.nil? ? {} : JSON.parse(h) }
              redis.hset("settings", id, settings.merge("recovered_disabled" => true).to_json)
              bot.api.send_message(chat_id: id, text: "Done!")
            when "enable_recovered"
              settings = redis.hget("settings", id).then { |h| h.nil? ? {} : JSON.parse(h) }
              redis.hset("settings", id, settings.merge("recovered_disabled" => false).to_json)
              bot.api.send_message(chat_id: id, text: "Done!")
            end
          when Telegram::Bot::Types::Message
            recovered_disabled = redis.hget("settings", message.chat.id).then { |h| h.nil? ? {} : JSON.parse(h) }.then { |h| h["recovered_disabled"] }

            case message.text
            when nil # apparently this is what happens when a bot is added/removed to a group chat
              if message.left_chat_member
                redis.srem("clients", message.chat.id)
                redis.srem("zeit_clients", message.chat.id)
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
                text: "Oh and... I subscribed you to updates of RKI and Die Zeit. So whenever they update their data I will let you know. /unsub if you don't want that."
              )
            when %r{^/jhu}
              redis.incr "called"
              bot.api.send_message(
                chat_id: message.chat.id,
                text: "John Hopkins says... #{FACE_WITH_THERMOMETER}"
              )

              data, last_updated = Source::JohnHopkins.new(redis: redis).fetch
              labels = %w[Country Confirmed Deaths]
              labels << "Recovered" unless recovered_disabled
              bot.api.send_message(
                chat_id: message.chat.id,
                text: "*Last updated at #{last_updated} \n#{labels.join(' | ')}\nPercentage: Compared to previous day*",
                parse_mode: "Markdown"
              )

              data.map! do |country, con, con_inc, deaths, deaths_inc, rec, rec_inc|
                [
                  country,
                  "#{con} #{percent(con_inc)}",
                  "#{deaths} #{percent(deaths_inc)}",
                  ("#{rec} #{percent(rec_inc)}" unless recovered_disabled)
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
            when %r{^/rki}
              is_subscribed = redis.sismember "clients", message.chat.id
              from = message.from
              data = { f: from.first_name, l: from.last_name, u: from.username }
              redis.hset "users", from.id, data.to_json

              redis.incr "called"

              bot.api.send_message(
                chat_id: message.chat.id,
                text: "Robert Koch sagt... #{FACE_WITH_MEDICAL_MASK}"
              )

              unless is_subscribed
                bot.api.send_message(
                  chat_id: message.chat.id,
                  text: "/sub um Notifications zu erhalten"
                )
              end

              stats, last_updated = Source::Rki.new(redis: redis).fetch

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
            when %r{^/zeit}
              is_subscribed = redis.sismember "zeit_clients", message.chat.id
              redis.incr "called"
              bot.api.send_message(
                chat_id: message.chat.id,
                text: "Die Zeit sagt... #{FACE_NAUSEATED}"
              )

              unless is_subscribed
                bot.api.send_message(
                  chat_id: message.chat.id,
                  text: "/sub um Notifications zu erhalten"
                )
              end

              data, last_updated = Source::DieZeit.new(redis: redis).fetch
              data.map! do |country, con, con_inc, deaths, deaths_inc, rec, rec_inc|
                [
                  country,
                  "#{con} #{percent(con_inc)}",
                  "#{deaths} #{percent(deaths_inc)}",
                  ("#{rec} #{percent(rec_inc)}" unless recovered_disabled)
                ].compact
              end

              labels = %w[Land Infizierte Todesfälle]
              labels << "Genesene" unless recovered_disabled
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
            when %r{^/sub}
              kb = [
                Telegram::Bot::Types::InlineKeyboardButton.new(text: "Robert Koch", callback_data: "sub_rki"),
                Telegram::Bot::Types::InlineKeyboardButton.new(text: "Die Zeit", callback_data: "sub_zeit")
              ]
              markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
              bot.api.send_message(chat_id: message.chat.id, text: "Which stats do you want to get updates for?", reply_markup: markup)
            when %r{^/unsub}
              kb = [
                Telegram::Bot::Types::InlineKeyboardButton.new(text: "Robert Koch", callback_data: "unsub_rki"),
                Telegram::Bot::Types::InlineKeyboardButton.new(text: "Die Zeit", callback_data: "unsub_zeit")
              ]
              markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
              bot.api.send_message(chat_id: message.chat.id, text: "Alright. Which source do you want to stop receiving updates from?", reply_markup: markup)
            when %r{^/pref}
              recovered_disabled = redis.hget("settings", message.chat.id).then { |h| h.nil? ? {} : JSON.parse(h) }.then { |h| h["recovered_disabled"] }
              kb = if recovered_disabled
                     [Telegram::Bot::Types::InlineKeyboardButton.new(text: "Enable the 'recovered' column", callback_data: "enable_recovered")]
                   else
                     [Telegram::Bot::Types::InlineKeyboardButton.new(text: "Disable the 'recovered' column (great for small devices)", callback_data: "disable_recovered")]
                   end
              markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
              bot.api.send_message(chat_id: message.chat.id, text: "What do you want to do?", reply_markup: markup)
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

    def percent(val)
      val.zero? ? "-" : "#{format('%+d', val)}%"
    end
  end
end
