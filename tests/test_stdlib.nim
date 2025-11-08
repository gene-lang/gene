import os
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

# putEnv("__GENE_TEST_ENV__", "gene_value")
# delEnv("__GENE_TEST_MISSING__")
# refresh_env_map()

# test_vm "$env", proc(result: Value) =
#   check result.kind == VkMap
#   let envKey = "__GENE_TEST_ENV__".to_key()
#   check envKey in result.ref.map
#   let value = result.ref.map[envKey]
#   check value.kind == VkString
#   check value.str == "gene_value"

# test_vm "$env/__GENE_TEST_ENV__", proc(result: Value) =
#   check result.kind == VkString
#   check result.str == "gene_value"

# test_vm """
#   ($env .get "__GENE_TEST_MISSING__")
# """, proc(result: Value) =
#   check result == NIL

# test_vm """
#   ($env .get "__GENE_TEST_MISSING__" "fallback")
# """, proc(result: Value) =
#   check result.kind == VkString
#   check result.str == "fallback"

# init_all()
# set_cmd_args(@["script.gene", "123"])

# test_vm "$cmd_args/0", proc(result: Value) =
#   check result.kind == VkString
#   check result.str == "script.gene"

# test_vm "$cmd_args/1", proc(result: Value) =
#   check result.kind == VkString
#   check result.str == "123"

# test_vm """
#   ($if_main
#     42)
# """, 42.to_value()
