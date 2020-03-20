# frozen_string_literal: true

module CovidBot
  module Logging
    def logger
      Logging.logger
    end

    def self.logger
      @logger ||= Logger.new($stdout)
    end
  end
end
