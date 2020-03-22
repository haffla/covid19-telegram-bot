# frozen_string_literal: true

module CovidBot
  module Source
    class Base
      def initialize(redis:)
        @redis = redis
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
              t >= 10_000 ? SI.convert(t) : t,
              y.to_i.zero? ? 0 : (((t - y) / y.to_f) * 100).round(2)
            ]
          end.then { |res| [state, *res] }
        end
      end

      def sorted(data)
        data.sort_by { _1[1] * -1 }
      end
    end
  end
end
