# frozen_string_literal: true

module CovidBot
  module Source
    class DieZeit < Base
      attr_reader :redis

      def fetch(last_updated_only: false)
        resp = HTTParty.get("https://interactive.zeit.de/cronjobs/2020/corona/bundeslaender-current.json")
        json = JSON.parse(resp.body)
        last_updated = json["lastUpdate"]
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

        last_updated = DateTime.parse(last_updated)
        t_inf, t_deaths, t_rec = json["totals"].values_at("count", "dead", "recovered")
        states << ["Ges", t_inf, t_deaths, t_rec]
        y_key = (last_updated - 1).strftime("%d.%m.%y") + "_zeit"
        with_comparison_to_previous(states, redis.get(y_key)).then do |res|
          k = last_updated.strftime("%d.%m.%y") + "_zeit"
          redis.set(k, states.to_json)
          [res, last_updated.strftime("%d.%m.%Y %H:%M")]
        end
      end
    end
  end
end
