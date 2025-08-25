#!/usr/bin/env ruby
class A
  def fib(n)
    n < 2 ? n : fib(n - 1) + fib(n - 2)
  end
end

a = A.new
before = Time.now
puts a.fib(24)
puts "Used time: #{Time.now - before}"
