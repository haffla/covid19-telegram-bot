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

        last_updated = Time.parse(last_updated)
        p_key = (last_updated - 3600 * 24).strftime("%y.%m.%d") + "_ju"
        with_comparison_to_previous(data, redis.get(p_key)).then do |result|
          redis.set(time.strftime("%y.%m.%d") + "_ju", data.to_json)
          [
            result.then { |r| r.first(26).uniq },
            last_updated.strftime("%d/%m/%Y %H:%M GMT")
          ]
        end
      end

      private

      def process(json)
        top = json["locations"].group_by { |c| c["country_code"] }.map do |country, c|
          [
            country,
            c.sum { |r| r["latest"]["confirmed"] },
            c.sum { |r| r["latest"]["deaths"] }
          ]
        end

        totals = [
          "--",
          json["latest"]["confirmed"],
          json["latest"]["deaths"]
        ]

        last_updated_location = json["locations"].max_by { |l| Time.parse(l["last_updated"]) }

        [[totals] + top, last_updated_location["last_updated"]]
      end

      def source_url
        "https://coronavirus-tracker-api.herokuapp.com/v2/locations"
      end
    end
  end
end
