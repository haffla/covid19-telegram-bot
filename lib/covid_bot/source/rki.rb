# frozen_string_literal: true

module CovidBot
  module Source
    class Rki < Base
      attr_reader :redis

      URL = "https://www.rki.de/DE/Content/InfAZ/N/Neuartiges_Coronavirus/Fallzahlen.html"

      def fetch(last_updated_only: false)
        body = redis.get("RKI_BODY").then do |r|
          if r.nil?
            b = HTTParty.get(URL).body
            redis.set("RKI_BODY", b, ex: 60 * 30)
            b
          else
            r
          end
        end

        doc = Nokogiri::HTML(body)
        last_updated = doc.at('h2:contains("Fallzahlen in Deutschland")').next_element.text
        return last_updated if last_updated_only

        today = doc.css("table tbody tr").map do |tr|
          tr.children.first(5).map { |e| e.children.first.text }
        end.map do |state, inf, _, _, deaths|
          infected = inf.gsub(".", "").to_i
          deaths = deaths.gsub(".", "").to_i
          state = if state.include?("-")
                    state.split("-").map { |s| s[0] }.join("-")
                  else
                    state[0..2]
                  end
          [state, infected, deaths]
        end

        last_updated_ts = last_updated.scan(/\d+\.\d+\.\d+/).first
        last_updated_ts = Date.parse(last_updated_ts).to_time
        # under this key stats from yesterday are saved
        y_key = (last_updated_ts - 3600 * 24).strftime("%y.%m.%d") + "_rki"
        with_comparison_to_previous(today, redis.get(y_key)).then do |result|
          redis.set(last_updated_ts.strftime("%y.%m.%d") + "_rki", today.to_json)
          [result, last_updated]
        end
      end
    end
  end
end