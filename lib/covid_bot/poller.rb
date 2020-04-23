# frozen_string_literal: true

module CovidBot
  class Poller
    include Logging

    attr_reader :redis, :bot

    def initialize(redis:, bot:)
      @redis = redis
      @bot = bot
    end

    def start
      Thread.new do
        Raven.capture do
          loop do
            poll
            sleep 600
          end
        end
      end
    end

    def poll
      logger.info "🤖 Polling for updates"
      poll_rki
      poll_zeit
      poll_jhu
    end

    def poll_rki
      instance = Source::Rki.new(redis: redis)
      redis_key = "rki_last_updated_at"
      message = "🤖 Das RKI hat neue Zahlen: /rki. Nervt? /unsub"
      clients_key = "clients"
      do_poll(instance, redis_key, message, clients_key)
    end

    def poll_zeit
      instance = Source::DieZeit.new(redis: redis)
      redis_key = "zeit_last_updated_at"
      message = "🤖 Die Zeit hat neue Zahlen: /zeit. Nervt? /unsub"
      clients_key = "zeit_clients"
      do_poll(instance, redis_key, message, clients_key)
    end

    def poll_jhu
      instance = Source::JohnsHopkins.new(redis: redis)
      redis_key = "jhu_last_updated_at"
      message = "🤖 Johns Hopkins got new data: /jhu. Stop receiving notifications? /unsub"
      clients_key = "jhu_clients"
      do_poll(instance, redis_key, message, clients_key)
    end

    def do_poll(instance, redis_key, message, clients_key)
      last_updated = instance.fetch[1]

      redis.get(redis_key).then do |r|
        if r != last_updated
          redis.set(redis_key, last_updated)
          unless r.nil?
            clients = redis.smembers(clients_key) || []
            instance.purge_cache if clients.any?
            logger.info "Delivering message to #{clients.size} clients"
            clients.each do |client|
              bot.api.send_message(
                chat_id: client,
                text: message,
                parse_mode: "Markdown"
              )
            rescue StandardError => e
              redis.srem(clients_key, client)
              logger.fatal("Error sending message to client #{client}: #{e.full_message}")
              Raven.capture_exception(e)
            end
          end
        end
      end
    end
  end
end
