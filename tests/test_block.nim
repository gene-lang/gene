import unittest

import gene/types except Exception

import ./helpers

# Support special variables to access positional arguments?
#   E.g. $0, $1, $-1(last)

test_vm """
  (->)
""", proc(r: Value) =
  check r.ref.kind == VkBlock

test_vm """
  (a -> a)
""", proc(r: Value) =
  check r.ref.kind == VkBlock

test_vm """
  (fn f b
    (b)
  )
  (f (-> 1))
""", 1

test_vm """
  (fn f b
    (b 2)
  )
  (f (a -> (a + 1)))
""", 3
