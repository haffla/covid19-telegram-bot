# frozen_string_literal: true

require "rack"
require "redis"
require "json"
require "date"

class Application
  attr_reader :redis

  def initialize
    @redis = Redis.new
    @path = ENV["SECRET_PATH"]
  end

  def call(env)
    req = Rack::Request.new(env)
    if req.get? && req.path == @path
      [200, {}, [body]]
    else
      [400, {}, []]
    end
  end

  def body
    users = redis.hgetall("users").transform_values { JSON.parse(_1) }
    rki_clients = redis.smembers("clients").map { users[_1] }.compact.sort_by do |el|
      el["last"].then { _1.nil? ? DateTime.new : DateTime.parse(_1) }
    end.reverse!
    zeit_clients = redis.smembers("zeit_clients").map { users[_1] }.compact.sort_by do |el|
      el["last"].then { _1.nil? ? DateTime.new : DateTime.parse(_1) }
    end.reverse!

    {
      clients: {
        rki: rki_clients,
        zeit: zeit_clients
      },
      called: {
        rki: redis.get("called_rki").to_i,
        zeit: redis.get("called_zeit").to_i,
        jhu: redis.get("called_jhu").to_i
      }
    }.to_json
  end
end

Rack::Handler::WEBrick.run Application.new, Port: ENV["PORT"] || 9292
