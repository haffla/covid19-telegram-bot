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

      def fetch_source(url = source_url)
        http_get url
      end

      def purge_cache(url = source_url)
        redis.del url
      end

      def with_data_cache(url = source_url)
        redis.get(url).then do |data|
          next JSON.parse(data) if data

          data = yield
          redis.set(url, data.to_json, ex: 3600)
          data
        end
      end

      def sorted(data)
        data.sort_by { _1[1] * -1 }
      end
    end
  end
end
