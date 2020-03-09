require "httparty"

class CovidStats
  def self.fetch
    HTTParty.get("https://raw.githubusercontent.com/iceweasel1/COVID-19-Germany/master/germany_with_source.csv").then do |resp|
      csv = CSV.parse(resp.body)
      berlin = csv.sum { |row| row[2] == "Berlin" ? 1 : 0 }
      [csv.size, berlin]
    end
  end
end
