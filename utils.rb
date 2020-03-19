def to_utf8(c)
  c.chr Encoding::UTF_8
end

def percent(val)
  val.zero? ? "-" : "#{format('%+d', val)}%"
end

