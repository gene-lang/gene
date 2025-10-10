import os
import unittest
import tables

import gene/types

import ./helpers

# Macro support
#
# * A macro will generate an AST tree and pass back to the VM to execute.
#

# Basic macro-like function that returns its argument
test_vm """
  (fn m! [a]
    a
  )
  (m! b)
""", "b".to_symbol_value()

# Test that macro-like function arguments are not evaluated
test_vm """
  (fn m! [a]
    :macro_result
  )
  (m! (this_would_fail_if_evaluated))
""", "macro_result".to_symbol_value()

test_vm """
  (fn m! [a b]
    (+ ($caller_eval a) ($caller_eval b))
  )
  (m! 1 2)
""", 3

test_vm """
  (fn m! [a = 1]
    (+ ($caller_eval a) 2)
  )
  (m!)
""", 3

# Simple test without function wrapper
test_vm """
  (var a 1)
  (fn m! []
    ($caller_eval :a)
  )
  (m!)
""", 1

test_vm """
  (fn m! []
    ($caller_eval :a)
  )
  (fn f [_]
    (var a 1)
    (m!)
  )
  (f nil)
""", 1

test_vm """
  (var a 1)
  (fn m! [b]
    ($caller_eval b)
  )
  (m! a)
""", 1

putEnv("__GENE_TEST_ENV__", "gene_value")
delEnv("__GENE_TEST_MISSING__")
refresh_env_map()

test_vm "$env", proc(result: Value) =
  check result.kind == VkMap
  let envKey = "__GENE_TEST_ENV__".to_key()
  check envKey in result.ref.map
  let value = result.ref.map[envKey]
  check value.kind == VkString
  check value.str == "gene_value"

test_vm "$env/__GENE_TEST_ENV__", proc(result: Value) =
  check result.kind == VkString
  check result.str == "gene_value"

test_vm """
  ($env .get "__GENE_TEST_MISSING__")
""", proc(result: Value) =
  check result == NIL

test_vm """
  ($env .get "__GENE_TEST_MISSING__" "fallback")
""", proc(result: Value) =
  check result.kind == VkString
  check result.str == "fallback"

init_all()
set_cmd_args(@["script.gene", "123"])

test_vm "$cmd_args/0", proc(result: Value) =
  check result.kind == VkString
  check result.str == "script.gene"

test_vm "$cmd_args/1", proc(result: Value) =
  check result.kind == VkString
  check result.str == "123"

test_vm """
  ($if_main
    42)
""", 42.to_value()

# test_core """
#   (fn m! [_]
#     (class A
#       (.fn test [_] "A.test")
#     )
#     ($caller_eval
#       (:$def_ns_member "B" A)
#     )
#   )
#   (m! nil)
#   ((new B) .test)
# """, "A.test"

# test_core """
#   (fn m! [name]
#     (class A
#       (.fn test [_] "A.test")
#     )
#     ($caller_eval
#       (:$def_ns_member name A)
#     )
#   )
#   (m! "B")
#   ((new B) .test)
# """, "A.test"

# # TODO: this should be possible with macro/caller_eval etc
# test_vm """
#   (fn with! [name value body...]
#     (var expr
#       :(do
#         (var %name %value)
#         %body...
#         %name))
#     ($caller_eval expr)
#   )
#   (var b "b")
#   (with! a "a"
#     (a = (a b))
#   )
# """, "ab"
