import unittest

import gene/types except Exception

import ./helpers

# Anonymous macro: fnx! should leave arguments unevaluated
test_vm """
  (var quote (fnx! [x] x))
  (quote (throw "boom"))
""", proc(r: Value) =
  check r.kind == VkGene

# new! should be rejected when the class only has ctor (eager)
test_vm_error """
  (class Regular
    (.ctor []
      (/x = 1)
    )
  )
  (new! Regular)
"""

# new should be rejected when the class only has ctor! (lazy)
test_vm_error """
  (class MacroCtor
    (.ctor! [x]
      (/body = x)
    )
  )
  (new MacroCtor)
"""

# new! with ctor! delivers unevaluated arguments to the constructor
test_vm """
  (class MacroCtor
    (.ctor! [x]
      (/body = x)
    )
  )
  (var m (new! MacroCtor (+ 1 2)))
  m/body
""", proc(r: Value) =
  check r.kind == VkGene
