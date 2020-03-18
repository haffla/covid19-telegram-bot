class ZeitStats
  attr_reader :redis

  def fetch(last_updated_only: false)
    resp = HTTParty.get("https://interactive.zeit.de/cronjobs/2020/corona/data.json")
    json = JSON.parse(resp.body)
    last_updated = json["changeTimestamp"]
    return last_updated if last_updated_only

    states = json["states"].map do |s|
      state, infected, deaths, recovered = s.values_at("state", "count", "recovered", "dead")
      state = if state.include?("-")
                state.split("-").map { |s| s[0] }.join("-")
              else
                state[0..2]
              end
      [state, infected, deaths, recovered]
    end

    t_inf, t_deaths, t_rec = json["totals"].values_at("count", "dead", "recovered")
    states << ["Ges", t_inf, t_deaths, t_rec]
    [states, last_updated]
  end
end
