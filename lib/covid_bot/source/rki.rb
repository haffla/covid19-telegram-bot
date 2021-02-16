# frozen_string_literal: true

module CovidBot
  module Source
    class Rki < Base
      def fetch
        total_cases = 0
        total_delta = 0
        last_updated = 0
        total_population = 0
        total_cases_last_seven_days = 0

        json = with_data_cache(url_bundeslaender) do
          JSON.parse(fetch_source(url_bundeslaender))
        end

        bl_data = json["features"].map do |feat|
          bl, cases, updated, seven_day_i, population = feat["attributes"].values_at("LAN_ew_GEN", "Fallzahl",
                                                                                     "Aktualisierung", "cases7_bl_per_100k", "LAN_ew_EWZ")
          population_factor = population.to_d / 100_000
          total_cases += cases
          updated /= 1000
          last_updated = updated > last_updated ? updated : last_updated
          total_population += population
          total_cases_last_seven_days += (population_factor * seven_day_i)
          [bl, cases, seven_day_i.round(1)]
        end

        json = with_data_cache(url_new_cases) do
          JSON.parse(fetch_source(url_new_cases))
        end

        json["features"].each do |feat|
          delta, bundesland = feat["attributes"].values_at("value", "Bundesland")
          total_delta += delta
          bl_data.detect { |bl| bl.first == bundesland }.insert(2, delta)
        end

        population_factor = total_population / 100_000
        total_seven_day_i = total_cases_last_seven_days / population_factor
        bl_data.push(["Gesamt", total_cases, total_delta, total_seven_day_i.to_f.round(1)])

        # create short names of Bundesländer
        bl_data.each do |bl|
          bl[0] = bl[0].scan(/[A-Z]/).then do |capitals|
            capitals.size == 2 ? capitals.join("-") : bl[0][0..2]
          end
        end

        updated = "Aktualisierung: #{Time.at(last_updated).to_datetime.strftime('%d.%m.%Y')}"
        [sorted(bl_data), updated]
      end

      def url_bundeslaender
        "https://services7.arcgis.com/mOBPykOjAyBO2ZKk/arcgis/rest/services/Coronaf%C3%A4lle_in_den_Bundesl%C3%A4ndern/FeatureServer/0/query?where=1%3D1&objectIds=&time=&geometry=&geometryType=esriGeometryEnvelope&inSR=&spatialRel=esriSpatialRelIntersects&resultType=none&distance=0.0&units=esriSRUnit_Meter&returnGeodetic=false&outFields=*&returnGeometry=false&returnCentroid=false&featureEncoding=esriDefault&multipatchOption=xyFootprint&maxAllowableOffset=&geometryPrecision=&outSR=&datumTransformation=&applyVCSProjection=false&returnIdsOnly=false&returnUniqueIdsOnly=false&returnCountOnly=false&returnExtentOnly=false&returnQueryGeometry=false&returnDistinctValues=false&cacheHint=false&orderByFields=&groupByFieldsForStatistics=&outStatistics=&having=&resultOffset=&resultRecordCount=&returnZ=false&returnM=false&returnExceededLimitFeatures=true&quantizationParameters=&sqlFormat=none&f=pjson"
      end

      def url_new_cases
        "https://services7.arcgis.com/mOBPykOjAyBO2ZKk/arcgis/rest/services/RKI_COVID19/FeatureServer/0/query?where=NeuerFall+IN%281%2C+-1%29&objectIds=&time=&resultType=standard&outFields=*&returnIdsOnly=false&returnUniqueIdsOnly=false&returnCountOnly=false&returnDistinctValues=false&cacheHint=true&orderByFields=&groupByFieldsForStatistics=Bundesland&outStatistics=%5B%7B%22statisticType%22%3A%22sum%22%2C%22onStatisticField%22%3A%22AnzahlFall%22%2C%22outStatisticFieldName%22%3A%22value%22%7D%5D&having=&resultOffset=&resultRecordCount=&sqlFormat=none&f=pjson"
      end

      def purge_cache
        super(url_bundeslaender)
        super(url_new_cases)
      end
    end
  end
end
