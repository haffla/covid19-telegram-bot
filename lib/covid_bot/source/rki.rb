# frozen_string_literal: true

module CovidBot
  module Source
    class Rki < Base
      def source_url
        "https://www.rki.de/DE/Content/InfAZ/N/Neuartiges_Coronavirus/Fallzahlen.html"
      end

      def fetch
        today, last_updated = with_data_cache do
          doc = Nokogiri::HTML(fetch_source)
          last_updated = doc.at('h3:contains("Fallzahlen in Deutschland")').next_element.text
          today = doc.css("table tbody tr").map do |tr|
            tr.children.map { |e| e.text }
          end.map do |state, inf, inf_delta, _, _, deaths|
            infected = inf&.gsub(".", "").to_i
            infected_delta = inf_delta.gsub("+", "").to_i
            deaths = deaths&.gsub(".", "").to_i
            state = state.scan(/[A-Z]/).then do |capitals|
              capitals.size == 2 ? capitals.join("-") : state[0..2]
            end
            [state, infected, infected_delta, deaths]
          end

          [today, last_updated]
        end
      end
    end
  end
end
