import unittest

import gene/types except Exception

import ./helpers

# Super call to parent eager method

test_vm """
  (class Base
    (.ctor [x] (/x = x))
    (.fn add [y]
      (+ /x y)
    )
  )
  (class Child < Base
    (.ctor [x]
      (super .ctor x)
    )
    (.fn add [y]
      (super .add y)
    )
  )
  (var c (new Child 2))
  (c .add 3)
""", 5.to_value()

# Super call to parent macro method should preserve unevaluated args

test_vm """
  (class Base
    (.fn m! [x] x)
  )
  (class Child < Base
    (.fn m! [x]
      (super .m! (+ 1 2))
    )
  )
  ((new Child) .m! 0)
""", proc(v: Value) =
  check v.kind == VkGene

# Super call to parent macro constructor

test_vm """
  (class Base
    (.ctor! [expr]
      (/body = expr)
    )
  )
  (class Child < Base
    (.ctor! [expr]
      (super .ctor! expr)
    )
  )
  (var c (new! Child (+ 1 2)))
  c/body
""", proc(v: Value) =
  check v.kind == VkGene
