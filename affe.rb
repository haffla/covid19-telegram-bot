# frozen_string_literal: true

def calc(amount, annual_return, years, savings)
  return savings if years < 1

  savings = (savings + amount * 12).then { |s| s + s * annual_return }
  calc(amount, annual_return, years - 1, savings)
end

pp calc(300, 0.1, 35, 0)
