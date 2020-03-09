require "httparty"

class CovidStats
  def self.fetch
    HTTParty.get("https://raw.githubusercontent.com/iceweasel1/COVID-19-Germany/master/germany_with_source.csv").then do |resp|
      csv = CSV.parse(resp.body)
      berlin = csv.sum { |row| row[2] == "Berlin" ? 1 : 0 }
      nk = csv.sum { |row| row[3].match?(/Neuköll?n/) ? 1 : 0 }
      kb = csv.sum { |row| row[3] == "Friedrichshain-Kreuzberg" ? 1 : 0 }
      pan = csv.sum { |row| row[3] == "Pankow" ? 1 : 0 }
      [csv.size, berlin, nk, kb, pan]
    end
  end
end
