# frozen_string_literal: true

module CovidBot
  module Source
    class Base
      attr_reader :redis

      def initialize(redis:)
        @redis = redis
      end

      def http_get(source)
        resp = HTTParty.get(source)
        return resp.body if resp.code < 300
      end

      def fetch_source
        http_get source_url
      end

      def purge_cache
        redis.del source_url
      end

      def with_comparison_to_previous(today, yesterday)
        y_hist = yesterday.then do |h|
          if h.nil?
            today
          else
            JSON.parse(h).map { |state, *numbers| [state, *numbers.map(&:to_i)] }
          end
        end.to_h { |state, *numbers| [state, numbers] }

        sorted(today).filter_map do |state, *numbers|
          y_numbers = y_hist[state] || []

          numbers.zip(y_numbers).flat_map do |t, y|
            [
              t,
              t - y
            ]
          end.then { |res| [state, *res] }
        end
      end

      def with_data_cache
        redis.get(source_url).then do |data|
          next JSON.parse(data) if data

          data = yield
          redis.set(source_url, data.to_json, ex: 3600)
          data
        end
      end

      def sorted(data)
        data.sort_by { _1[1] * -1 }
      end
    end
  end
end
