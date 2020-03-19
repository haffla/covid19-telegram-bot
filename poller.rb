# frozen_string_literal: true

require_relative "./utils"
require_relative "./zeit_stats"
require_relative "./covid_rki_stats"

class Poller
  attr_reader :redis, :bot

  FACE_ROBOT = to_utf8(0x1F916)

  def initialize(redis:, bot:)
    @redis = redis
    @bot = bot
  end

  def start
    task = Concurrent::TimerTask.new(execution_interval: 600, run_now: true) { poll }

    task.execute
  end

  def poll
    poll_rki
    poll_zeit
  end

  def poll_rki
    instance = CovidRkiStats.new(redis: redis)
    redis_key = "rki_last_updated_at"
    message = "#{FACE_ROBOT} Das RKI hat neue Zahlen: /rki. Nervt? /unsub"
    clients_key = "clients"
    do_poll(instance, redis_key, message, clients_key) do
      redis.del("RKI_BODY")
    end
  end

  def poll_zeit
    instance = ZeitStats.new(redis: redis)
    redis_key = "zeit_last_updated_at"
    message = "#{FACE_ROBOT} Die Zeit hat neue Zahlen: /zeit. Nervt? /unsub"
    clients_key = "zeit_clients"
    do_poll(instance, redis_key, message, clients_key)
  end

  def do_poll(instance, redis_key, message, clients_key)
    last_updated = instance.fetch(last_updated_only: true)

    redis.get(redis_key).then do |r|
      if r != last_updated
        redis.set(redis_key, last_updated)
        unless r.nil?
          yield if block_given?
          clients = redis.smembers(clients_key)
          clients.each do |client|
            begin
              bot.api.send_message(
                chat_id: client,
                text: message,
                parse_mode: "Markdown"
              )
            rescue
              redis.srem(clients_key, client)
            end
          end
        end
      end
    end
  end
end
