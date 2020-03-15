# frozen_string_literal: true

require "httparty"

class JohnHopkinsStats
  attr_reader :redis

  def initialize(redis:)
    @redis = redis
  end

  def fetch
    time = Time.now
    resp = HTTParty.get(source_url(time))
    if resp.code == 404
      time -= 3600 * 24
      resp = HTTParty.get(source_url(time))
    end

    csv = CSV.parse(resp.body)

    resp = HTTParty.get(commit_url(time))
    last_updated = JSON.parse(resp.body).first["commit"]["committer"]["date"].then do |d|
      Time.parse(d)
    end

    data = process_csv(csv)
    [data, last_updated.strftime("%d/%m/%Y %H:%M GMT")]
  end

  private

  def process_csv(csv)
    top = csv.select { |r| r[3].to_i >= 1_000 }.map do |prov, country, _, conf, dead, recov|
      [
        [prov, country].compact.uniq.join("-"),
        conf.to_i,
        dead.to_i,
        recov.to_i
      ]
    end

    totals = csv.each_with_object([0, 0, 0]) do |r, carry|
      carry[0] += r[3].to_i
      carry[1] += r[4].to_i
      carry[2] += r[5].to_i
    end

    top << (["Earth"] + totals)
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
