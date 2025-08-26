import unittest
import ../src/gene/types
import ../src/gene/parser
import ../src/gene/compiler
import ../src/gene/vm
import ../src/gene/vm/core

suite "Generator Functions":
  setup:
    var app = new_app()
    App.init(app)

  test "Simple generator function":
    let code = """
(fn counter* [n]
  (var i 0)
  (while (< i n)
    (yield i)
    (i = (+ i 1))))

(var gen (counter* 3))
(assert (== (gen .next) 0))
(assert (== (gen .next) 1))
(assert (== (gen .next) 2))
(assert (== (gen .next) void))
"""
    let parsed = read(code)
    let compiled = compile(parsed)
    discard run(compiled)

  test "Generator with state preservation":
    let code = """
(fn fibonacci* [n]
  (var a 0)
  (var b 1)
  (var count 0)
  (while (< count n)
    (yield a)
    (var temp (+ a b))
    (a = b)
    (b = temp)
    (count = (+ count 1))))

(var fib (fibonacci* 5))
(assert (== (fib .next) 0))
(assert (== (fib .next) 1))
(assert (== (fib .next) 1))
(assert (== (fib .next) 2))
(assert (== (fib .next) 3))
(assert (== (fib .next) void))
"""
    let parsed = read(code)
    let compiled = compile(parsed)
    discard run(compiled)

  test "Anonymous generator function":
    let code = """
(var gen (fn ^^generator _ [max]
  (var i 0)
  (while (< i max)
    (yield (* i i))
    (i = (+ i 1)))))

(var squares (gen 4))
(assert (== (squares .next) 0))
(assert (== (squares .next) 1))
(assert (== (squares .next) 4))
(assert (== (squares .next) 9))
(assert (== (squares .next) void))
"""
    let parsed = read(code)
    let compiled = compile(parsed)
    discard run(compiled)

  test "Multiple generator instances":
    let code = """
(fn counter* [start]
  (var i start)
  (while (< i (+ start 3))
    (yield i)
    (i = (+ i 1))))

(var gen1 (counter* 0))
(var gen2 (counter* 10))

(assert (== (gen1 .next) 0))
(assert (== (gen2 .next) 10))
(assert (== (gen1 .next) 1))
(assert (== (gen2 .next) 11))
(assert (== (gen1 .next) 2))
(assert (== (gen2 .next) 12))
"""
    let parsed = read(code)
    let compiled = compile(parsed)
    discard run(compiled)

  test "Empty generator":
    let code = """
(fn empty* []
  nil)

(var gen (empty*))
(assert (== (gen .next) void))
(assert (== (gen .next) void))
"""
    let parsed = read(code)
    let compiled = compile(parsed)
    discard run(compiled)

  test "Generator with single yield":
    let code = """
(fn single* []
  (yield 42))

(var gen (single*))
(assert (== (gen .next) 42))
(assert (== (gen .next) void))
"""
    let parsed = read(code)
    let compiled = compile(parsed)
    discard run(compiled)

  test "Generator with complex expressions":
    let code = """
(fn complex* []
  (var x 1)
  (yield x)
  (x = (* x 2))
  (yield x)
  (x = (+ x 3))
  (yield x))

(var gen (complex*))
(assert (== (gen .next) 1))
(assert (== (gen .next) 2))
(assert (== (gen .next) 5))
(assert (== (gen .next) void))
"""
    let parsed = read(code)
    let compiled = compile(parsed)
    discard run(compiled)

  test "Generator yielding void":
    let code = """
(fn void-gen* []
  (yield 1)
  (yield void)
  (yield 3))

(var gen (void-gen*))
(assert (== (gen .next) 1))
(assert (== (gen .next) void))
(assert (== (gen .next) 3))
(assert (== (gen .next) void))
"""
    let parsed = read(code)
    let compiled = compile(parsed)
    discard run(compiled)

  test "Nested generators":
    let code = """
(fn outer* []
  (fn inner* []
    (yield 1)
    (yield 2))
  (var inner-gen (inner*))
  (yield (inner-gen .next))
  (yield (inner-gen .next))
  (yield 3))

(var gen (outer*))
(assert (== (gen .next) 1))
(assert (== (gen .next) 2))
(assert (== (gen .next) 3))
(assert (== (gen .next) void))
"""
    let parsed = read(code)
    let compiled = compile(parsed)
    discard run(compiled)

  test "Generator in higher-order function":
    let code = """
(fn make-counter* [start]
  (fn counter* []
    (var i start)
    (while true
      (yield i)
      (i = (+ i 1))))
  counter*)

(var counter-fn (make-counter* 5))
(var gen (counter-fn))
(assert (== (gen .next) 5))
(assert (== (gen .next) 6))
(assert (== (gen .next) 7))
"""
    let parsed = read(code)
    let compiled = compile(parsed)
    discard run(compiled)