# frozen_string_literal: true

class MdTable
  def self.make(data:)
    justs = data.transpose.map do |col|
      col.inject(0) { |cur, s| cur >= s.to_s.size ? cur : s.to_s.size }
    end

    data.map do |row|
      row.each_with_index.map do |c, i|
        c.to_s.ljust(justs[i], " ")
      end.join(" | ")
    end.join("\n")
  end
end
