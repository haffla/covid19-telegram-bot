# frozen_string_literal: true

module CovidBot
  module Source
    class JohnHopkins
      attr_reader :redis

      def initialize(redis:)
        @redis = redis
      end

      def fetch(time: Time.now.utc)
        resp = HTTParty.get(source_url(time))
        while resp.code == 404
          time -= 3600 * 24
          resp = HTTParty.get(source_url(time))
        end

        csv = CSV.parse(resp.body)

        commits = JSON.parse(
          HTTParty.get(
            commit_url(time)
          ).body
        )

        last_updated = commits.first["commit"]["committer"]["date"].then do |d|
          Time.parse(d)
        end

        data = process_csv(csv[1..-1])

        p_key = (time - 3600 * 24).strftime("%y.%m.%d") + "_ju"
        with_comparison_to_previous(data, redis.get(p_key)).then do |result|
          redis.set(time.strftime("%y.%m.%d") + "_ju", data.to_json)
          [
            result.then { |r| (r.first(15) << r.last).uniq },
            last_updated.strftime("%d/%m/%Y %H:%M GMT")
          ]
        end
      end

      private

      def process_csv(csv)
        top = csv.group_by { |c| c[1] }.filter_map do |country, c|
          country = ISO3166::Country.new(country) || ISO3166::Country.find_country_by_name(country)
          next if country.nil?

          [
            country.alpha3,
            c.sum { |r| r[3].to_i }, # confirmed
            c.sum { |r| r[4].to_i }, # deaths
            c.sum { |r| r[5].to_i }  # recovered
          ]
        end

        totals = csv.each_with_object([0, 0, 0]) do |r, carry|
          carry[0] += r[3].to_i
          carry[1] += r[4].to_i
          carry[2] += r[5].to_i
        end

        top << (["All"] + totals)
      end

      def with_comparison_to_previous(current, previous)
        p_hist = previous.then do |h|
          if h.nil?
            current
          else
            JSON.parse(h).map { |country, confirmed, deaths, rec| [country, confirmed.to_i, deaths.to_i, rec.to_i] }
          end
        end.to_h { |country, confirmed, deaths, rec| [country, { confirmed: confirmed, deaths: deaths, rec: rec }] }

        current.map do |country, confirmed, deaths, rec|
          p_con, p_deaths, p_rec = p_hist[country]&.values_at(:confirmed, :deaths, :rec)
          next [country, confirmed, 0, deaths, 0, rec, 0] if p_con.nil?

          [
            country,
            confirmed.then { |x| x >= 10_000 ? SI.convert(x) : x },
            (((confirmed - p_con) / p_con.to_f) * 100).round(2),
            deaths.then { |x| x >= 10_000 ? SI.convert(x) : x },
            (((deaths - p_deaths) / p_deaths.to_f) * 100).round(2),
            rec.then { |x| x >= 10_000 ? SI.convert(x) : x },
            (((rec - p_rec) / p_rec.to_f) * 100).round(2)
          ]
        end
      end

      def source_url(time)
        s = time.strftime("%m-%d-%Y")
        "https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_daily_reports/#{s}.csv"
      end

      def commit_url(time)
        file = CGI.escape source_url(time).split("/").last(3).join("/")
        "https://api.github.com/repos/CSSEGISandData/COVID-19/commits?path=#{file}&page=1&per_page=1"
      end
    end
  end
end
