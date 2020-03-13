# frozen_string_literal: true

require "nokogiri"
require "httparty"
require "redis"

class CovidRkiStats
  attr_reader :redis

  URL = "https://www.rki.de/DE/Content/InfAZ/N/Neuartiges_Coronavirus/Fallzahlen.html"

  def initialize(redis:)
    @redis = redis
  end

  def fetch
    body = redis.get("RKI_BODY").then do |r|
      if r.nil?
        b = HTTParty.get(URL).body
        redis.set("RKI_BODY", b, ex: 3600)
        b
      else
        r
      end
    end
    doc = Nokogiri::HTML(body)
    last_updated = doc.at('h2:contains("Fallzahlen in Deutschland")').next_element.text

    data = doc.css("table tbody tr").map do |tr|
      tr.children.first(2).map { |e| e.children.first.text }
    end.map do |k, v|
      infected, dead = v.gsub(".", "").scan(/\d+/).map(&:to_i)
      k = if k.include?("-")
            k.split("-").map { |s| s[0] }.join("-")
          else
            k[0..2]
          end
      [k, infected, dead || 0]
    end

    with_comparison_to_previous(data, last_updated)
  end

  def with_comparison_to_previous(today, last_updated)
    y_key = (Time.now - 3600 * 24).strftime("%y.%m.%d") + "_rki"
    # yesterday stats
    y_hist = redis.get(y_key).then do |h|
      if h.nil?
        today
      else
        JSON.parse(h).map { |state, infected, dead| [state, infected.to_i, dead.to_i] }
      end
    end.to_h { |state, infected, dead| [state, { infected: infected, dead: dead }] }

    res = today.map do |state, infected, dead|
      y_infected, y_dead = y_hist[state].values_at(:infected, :dead)
      [
        state,
        infected,
        (((infected - y_infected) / y_infected.to_f) * 100).round(2),
        dead,
        y_dead.zero? ? dead : (((dead - y_dead) / y_dead.to_f) * 100).round(2)
      ]
    end

    [res, last_updated]
  end
end
