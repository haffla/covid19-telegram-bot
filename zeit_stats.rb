# frozen_string_literal: true

class ZeitStats
  attr_reader :redis

  def initialize(redis:)
    @redis = redis
  end

  MONTHS = {
    "März" => "March",
    "Mai" => "May",
    "Oktober" => "October",
    "Dezember" => "December"
  }.freeze

  def fetch(last_updated_only: false)
    resp = HTTParty.get("https://interactive.zeit.de/cronjobs/2020/corona/data.json")
    json = JSON.parse(resp.body)
    last_updated = json["changeTimestamp"]
    return last_updated if last_updated_only

    states = json["states"].map do |s|
      state, infected, recovered, deaths = s.values_at("state", "count", "recovered", "dead")
      state = if state.include?("-")
                state.split("-").map { |s| s[0] }.join("-")
              else
                state[0..2]
              end
      [state, infected, deaths, recovered]
    end

    last_updated_ts = parse_date(last_updated)
    t_inf, t_deaths, t_rec = json["totals"].values_at("count", "dead", "recovered")
    states << ["Ges", t_inf, t_deaths, t_rec]
    y_key = (last_updated_ts - 3600 * 24).strftime("%d.%m.%y") + "_zeit"
    with_comparison_to_previous(states, redis.get(y_key)).then do |res|
      k = last_updated_ts.strftime("%d.%m.%y") + "_zeit"
      redis.set(k, states.to_json)
      [res, last_updated]
    end
  end

  def parse_date(s)
    s = s.gsub(Regexp.union(MONTHS.keys), MONTHS)
    Date.parse(s).to_time
  end

  def with_comparison_to_previous(today, yesterday)
    y_hist = yesterday.then do |h|
      if h.nil?
        today
      else
        JSON.parse(h).map { |state, infected, dead, recovered| [state, infected.to_i, dead.to_i, recovered.to_i] }
      end
    end.to_h { |state, infected, dead, recovered| [state, { infected: infected, dead: dead, recovered: recovered }] }

    today.map do |state, infected, dead, recovered|
      y_infected, y_dead, y_recovered = y_hist[state].values_at(:infected, :dead, :recovered)
      [
        state,
        infected.then { |x| x >= 10_000 ? SI.convert(x) : x },
        (((infected - y_infected) / y_infected.to_f) * 100).round(2),
        dead.then { |x| x >= 10_000 ? SI.convert(x) : x },
        y_dead.zero? ? 0 : (((dead - y_dead) / y_dead.to_f) * 100).round(2),
        recovered.then { |x| x >= 10_000 ? SI.convert(x) : x },
        y_recovered.zero? ? 0 : (((recovered - y_recovered) / y_recovered.to_f) * 100).round(2)
      ]
    end
  end
end
