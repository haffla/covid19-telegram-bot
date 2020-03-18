# frozen_string_literal: true

#
# DEPRECATED. Source is not maintained anymore.

require "httparty"
require "redis"

class CovidIceweaselStats
  attr_reader :redis

  def initialize(redis:)
    @redis = redis
  end

  def fetch
    HTTParty.get("https://raw.githubusercontent.com/iceweasel1/COVID-19-Germany/master/germany_with_source.csv").then do |resp|
      csv = CSV.parse(resp.body)

      with_comparison_to_previous(
        total: csv.size,
        berlin: csv.sum { |row| row[2] == "Berlin" ? 1 : 0 },
        nk: csv.sum { |row| row[3].match?(/Neuköll?n/) ? 1 : 0 },
        kb: csv.sum { |row| row[3] == "Friedrichshain-Kreuzberg" ? 1 : 0 },
        pan: csv.sum { |row| row[3] == "Pankow" ? 1 : 0 }
      )
    end
  end

  def with_comparison_to_previous(today_hist)
    y_key = (Time.now - 3600 * 24).strftime("%y.%m.%d")
    # yesterday stats
    y_hist = redis.get(y_key).then do |h|
      if h.nil?
        today_hist
      else
        JSON.parse(h, symbolize_names: true).transform_values(&:to_i)
      end
    end

    today_hist.each_with_object({}) do |(k, current), hist|
      previous = y_hist[k]
      hist[k] = {
        current: current,
        previous: previous,
        increase: (((current - previous) / previous.to_f) * 100).round(2)
      }
    end.then do |h|
      key = Time.now.strftime("%y.%m.%d")
      redis.set(key, today_hist.to_json)

      h
    end
  end
end
