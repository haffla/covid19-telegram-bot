# frozen_string_literal: true

module CovidBot
  module Source
    class DieZeit < Base
      def source_url
        "https://interactive.zeit.de/cronjobs/2020/corona/germany.json"
      end

      def fetch
        states, last_updated, totals = with_data_cache do
          json = JSON.parse(fetch_source)
          last_updated = json["lastUpdate"]
          data = json["states"]["items"].map do |s|
            state = s["name"]
            current_stats = s["currentStats"]
            infected, recovered, deaths = current_stats.values_at("count", "recovered", "dead")
            state = if state.include?("-")
                      state.split("-").map { _1[0] }.join("-")
                    else
                      state[..2]
                    end
            [state, infected, deaths, recovered]
          end
          [data, last_updated, json["currentStats"]]
        end

        last_updated = DateTime.parse(last_updated)
        t_inf, t_deaths, t_rec = totals.values_at("count", "dead", "recovered")
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
