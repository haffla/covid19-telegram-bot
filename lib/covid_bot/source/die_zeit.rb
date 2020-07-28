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
            infected, deaths, active = current_stats.values_at("count", "dead", "active")
            state = if state.include?("-")
                      state.split("-").map { _1[0] }.join("-")
                    else
                      state[..2]
                    end
            [state, infected, deaths, active]
          end
          [data, DateTime.parse(last_updated), json["currentStats"]]
        end

        t_inf, t_deaths, t_active = totals.values_at("count", "dead", "active")
        states << ["Ges", t_inf, t_deaths, t_active]
        [sorted(states), last_updated]
      end
    end
  end
end
