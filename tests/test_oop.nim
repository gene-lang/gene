import unittest

import gene/types except Exception

import ./helpers

# OOP tests for VM implementation
# Only including tests that work with current VM capabilities

# Basic class creation
test_vm "(class A)", proc(r: Value) =
  check r.ref.class.name == "A"

# Basic object creation
test_vm """
  (class A)
  (new A)
""", proc(r: Value) =
  check r.ref.instance_class.name == "A"

# Multiple classes
test_vm """
  (class A)
  (class B)
  B
""", proc(r: Value) =
  check r.ref.class.name == "B"

# The following tests require features not yet fully implemented in VM:

# Class inheritance
test_vm """
  (class A)
  (class B < A)
  B
""", proc(r: Value) =
  check r.ref.class.name == "B"
  check r.ref.class.parent.name == "A"

# Namespace class definition
# test_vm """
#   (ns n
#     (ns m)
#   )
#   (class n/m/A)
#   n/m/A/.name
# """, "A"

# Nested class definition
test_vm """
  (class A
    (class B)
  )
  A/B
""", proc(r: Value) =
  check r.ref.class.name == "B"

# Constructor - needs method compilation
# test_vm """
#   (class A
#     (.ctor _
#       (/test = 1)
#     )
#   )
#   (var a (new A))
#   a/test
# """, 1

# Constructor with parameter shadowing
# test_vm """
#   (class A
#     (.ctor /test)
#   )
#   (var a (new A 1))
#   a/test
# """, 1

# Namespaced class - needs complex symbol support
# test_vm """
#   (ns n)
#   (class n/A)
#   n/A
# """, proc(r: Value) =
#   check r.class.name == "A"

# Methods - needs method compilation and calling
# test_vm """
#   (class A
#     (.fn test _
#       1
#     )
#   )
#   ((new A).test)
# """, 1

# Method invocation with dot syntax
# test_vm """
#   (class A
#     (.fn test _
#       1
#     )
#   )
#   (var a (new A))
#   a/.test
# """, 1

# Method with instance variable assignment
# test_vm """
#   (class A
#     (.fn set_x a
#       (/x = a)
#     )
#     (.fn test _
#       /x
#     )
#   )
#   (var a (new A))
#   (a .set_x 1)
#   (a .test)
# """, 1

# Instance variables - needs constructor support
# test_vm """
#   (class A
#     (.ctor _
#       (/a = 1)
#     )
#   )
#   (var x (new A))
#   x/a
# """, 1

# Method with parameters
# test_vm """
#   (class A
#     (.fn test a
#       a
#     )
#   )
#   ((new A).test 1)
# """, 1

# Inheritance with method override
# test_vm """
#   (class A
#     (.fn test []
#       "A.test"
#     )
#   )
#   (class B < A
#   )
#   ((new B) .test)
# """, "A.test"

# Super calls - TODO: implement super properly
# test_vm """
#   (class A
#     (.fn test a
#       a
#     )
#   )
#   (class B < A
#     (.fn test a
#       (super .test a)
#     )
#   )
#   ((new B) .test 1)
# """, 1

# Inherited constructor - TODO: need to call parent constructor
# test_vm """
#   (class A
#     (.ctor _
#       (/test = 1)
#     )
#   )
#   (class B < A)
#   (var b (new B))
#   b/test
# """, 1

# Mixins - TODO: implement mixin support
# test_vm """
#   (mixin M
#     (.fn test _
#       1
#     )
#   )
#   (class A
#     (include M)
#   )
#   ((new A) .test)
# """, 1

# Type checking
# test_vm """
#   ([] .is Array)
# """, true

# on_extended callback
# test_vm """
#   (class A
#     (var /children [])
#     (.on_extended
#       (fnx child
#         (/children .add child)
#       )
#     )
#   )
#   (class B < A)
#   A/children/.size
# """, 1

# Object syntax
# test_vm """
#   ($object a
#     (.fn test _
#       1
#     )
#   )
#   a/.test
# """, 1

# Macro-like methods in classes
# test_vm """
#   (class A
#     (.fn test! [a]
#       a
#     )
#   )
#   (var b 1)
#   ((new A) .test! b)
# """, new_gene_symbol("b")

# # Macro constructor test - constructor receives unevaluated arguments
# test_vm """
#   (class Point
#     (.ctor! [x y]
#       (/x = ($caller_eval x))
#       (/y = ($caller_eval y))
#     )
#     (.fn get_x []
#       /x
#     )
#   )
#   (var a 5)
#   (var p (new! Point a (+ 3 2)))
#   (p .get_x)
# """, 5

# Regular constructor for comparison
# test_vm """
#   (class Point
#     (.ctor [x y]
#       (/x = x)
#       (/y = y)
#     )
#     (.fn get_x []
#       /x
#     )
#   )
#   (var a 5)
#   (var p (new Point a (+ 3 2)))
#   (p .get_x)
# """, 5

# # Macro constructor with validation
# test_vm """
#   (class Validator
#     (.ctor! [expr]
#       # We can inspect the unevaluated expression
#       (if (== ($caller_eval expr) 42)
#         (/valid = true)
#         (/valid = false)
#       )
#     )
#     (.fn is_valid []
#       /valid
#     )
#   )
#   (var v (new! Validator (+ 40 2)))
#   (v .is_valid)
# """, true