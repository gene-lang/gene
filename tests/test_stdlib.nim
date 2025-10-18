import ./helpers

test_vm """
  ((nil .class).name)
""", "Nil"

test_vm """
  (nil .to_s)
""", ""

test_vm """
  (:a .to_s)
""", "a"

test_vm """
  ("a" .to_s)
""", "a"

test_vm """
  ([1 "a"] .to_s)
""", "[1 \"a\"]"

test_vm """
  ({^a "a"} .to_s)
""", "{^a \"a\"}"

test_vm """
  ((:x ^a "a" "b") .to_s)
""", "(x ^a \"a\" \"b\")"

test_vm """
  (class A
    (.fn call [x y]
      (x + y)
    )
  )
  (var a (new A))
  (a 1 2)
""", 3
