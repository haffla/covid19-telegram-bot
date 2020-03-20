# frozen_string_literal: true

module CovidBot
  class MdTable
    def self.make(data:)
      justs = data.transpose.map do |col|
        col.inject(0) { |cur, s| cur >= s.to_s.size ? cur : s.to_s.size }
      end

      data.map do |row|
        row.each_with_index.map do |c, i|
          c = c.to_s.strip
          m = c.scan(/\S+/)
          if m.size == 2
            # if we have exactly 2, left align the left part
            # and right align the right part
            l = m[0].ljust(justs[i], " ").reverse
            r = m[1].rjust(justs[i], " ").reverse

            l.gsub(/\s/).with_index { |_, idx| r[idx] }.reverse
          else
            c.ljust(justs[i], " ")
          end
        end.join(" | ")
      end.join("\n")
    end
  end
end
