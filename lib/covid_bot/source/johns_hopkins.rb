# frozen_string_literal: true

module CovidBot
  module Source
    class JohnsHopkins < Base
      def fetch
        time = Time.now.utc
        data, last_updated = with_data_cache do
          json = JSON.parse(fetch_source)
          process(json)
        end

        [
          sorted(data).first(26).uniq,
          last_updated
        ]
      end

      private

      def process(json)
        top = json["locations"].group_by { |c| c["country_code"] }.map do |country, c|
          previous, latest = c.flat_map { |x| x["timelines"]["confirmed"]["timeline"].keys }.uniq.last(2)
          confirmed = c.sum { |r| r["timelines"]["confirmed"]["timeline"][latest] }
          deaths = c.sum { |r| r["timelines"]["deaths"]["timeline"][latest] }
          delta_confirmed = confirmed - c.sum { |r| r["timelines"]["confirmed"]["timeline"][previous] }
          delta_deaths = deaths - c.sum { |r| r["timelines"]["deaths"]["timeline"][previous] }

          [
            country,
            confirmed,
            delta_confirmed,
            deaths,
            delta_deaths
          ]
        end

        totals = [
          "--",
          top.sum { |c| c[1] },
          top.sum { |c| c[2] },
          top.sum { |c| c[3] },
          top.sum { |c| c[4] }
        ]

        last_updated_location = json["locations"].max_by { |l| Time.parse(l["last_updated"]) }
        [[totals] + top, last_updated_location["last_updated"]]
      end

      def source_url
        # currently https://covid-tracker-us.herokuapp.com but could be deployed elsewhere
        ENV["JOHNS_HOPKINS_API_BASE_URL"] + "/v2/locations?timelines=1"
      end
    end
  end
end
