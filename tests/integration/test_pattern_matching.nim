import unittest, strutils

import gene/types except Exception
import gene/vm

import ../helpers

proc test_vm_error_contains(code: string, expected: openArray[string]) =
  var code = cleanup(code)
  test "Compilation & VM error contains: " & code:
    init_all()
    try:
      discard VM.exec(code, "test_code")
      fail()
    except CatchableError as e:
      let message = e.msg
      checkpoint("error message: " & message)
      for substring in expected:
        check message.contains(substring)

# Pattern Binding
#
# * Argument parsing
# * (var pattern input)
#   Binding works similar to argument parsing
# * Custom matchers can be created, which takes something and
#   returns a function that takes an input and a scope object and
#   parses the input and stores as one or multiple variables
# * Every standard type should have an adapter to allow pattern matching
#   to access its data easily
# * Support "|" for different branches
#

# Mode: argument, bind, ...
# When matching arguments, root level name will match first item in the input
# While (var name value) binds the whole value
#
# Root level
# (var name input)
#
# Child level
# (var [a? b] input) # "a" is optional, if input contains only one item, it'll be
#                      # assigned to "b"
# (var [a... b] input) # "a" will match 0 to many items, the last item is assigned to "b"
# (var [a = 1 b] input) # "a" is optional and has default value of 1
#
# Grandchild level
# (var [a b [c]] input) # "c" will match a grandchild
#
# Match properties
# (var [^a] input)  # "a" will match input's property "a"
# (var [^a!] input) # "a" will match input's property "a" and is required
# (var [^a: var_a] input) # "var_a" will match input's property "a"
# (var [^a: var_a = 1] input) # "var_a" will match input's property "a", and has default
#                               # value of 1
#
# Q: How do we match gene_type?
# A: Use "*" to signify it. like "^" to signify properties. It does not support optional,
#    default values etc
#    [*type] will assign gene_type to "type"
#    [*: [...]] "*:" or "*name:" will signify that next item matches gene_type's internal structure
#

test_vm """
  (fn f [a]
    a
  )
  (f 1)
""", 1

test_vm """
  (fn f [a b]
    (a + b)
  )
  (f 1 2)
""", 3

test_vm """
  (var a [1])
  a
""", proc(r: Value) =
  check r.kind == VkArray
  check array_data(r).len == 1
  check array_data(r)[0] == 1

# Array pattern matching
test_vm """
  (var [a] [1])
  a
""", 1

# Array pattern matching with multiple elements
test_vm """
  (var [a b] [1 2])
  (a + b)
""", 3

test_vm """
  (var [a = 1 b] [2])
  [a b]
""", proc(r: Value) =
  check r.kind == VkArray
  check array_data(r).len == 2
  check array_data(r)[0] == 1
  check array_data(r)[1] == 2

test_vm """
  (var [items... tail] [1 2 3 4])
  [items tail]
""", proc(r: Value) =
  check r.kind == VkArray
  check array_data(r).len == 2
  check array_data(r)[0].kind == VkArray
  check array_data(array_data(r)[0]).len == 3
  check array_data(array_data(r)[0])[0] == 1
  check array_data(array_data(r)[0])[1] == 2
  check array_data(array_data(r)[0])[2] == 3
  check array_data(r)[1] == 4

test_vm """
  (var [items ... tail] [1 2 3 4])
  [items tail]
""", proc(r: Value) =
  check r.kind == VkArray
  check array_data(r).len == 2
  check array_data(r)[0].kind == VkArray
  check array_data(array_data(r)[0]).len == 3
  check array_data(array_data(r)[0])[0] == 1
  check array_data(array_data(r)[0])[1] == 2
  check array_data(array_data(r)[0])[2] == 3
  check array_data(r)[1] == 4

test_vm """
  (var payload `(payload ^a 10 ^x 99 20 30 40))
  (var [^a b c... ^rest...] payload)
  [a b c rest/x]
""", proc(r: Value) =
  check r.kind == VkArray
  check array_data(r).len == 4
  check array_data(r)[0] == 10
  check array_data(r)[1] == 20
  check array_data(r)[2].kind == VkArray
  check array_data(array_data(r)[2]).len == 2
  check array_data(array_data(r)[2])[0] == 30
  check array_data(array_data(r)[2])[1] == 40
  check array_data(r)[3] == 99

test_vm_error_contains """
  (var [a b] [])
""", [
  "Destructuring pattern mismatch",
  "Expected 1 arguments, got 0",
]

test_vm_error_contains """
  (var [a] [1 2])
""", [
  "Destructuring pattern mismatch",
  "Expected 1 arguments, got 2",
]

test_vm_error_contains """
  (var [^a b c...] [1 2 3])
""", [
  "Destructuring pattern mismatch",
  "Missing keyword argument: a",
]

test_vm_error_contains """
  (var [^a] [1])
""", [
  "Destructuring pattern mismatch",
  "Missing keyword argument: a",
]

test_vm_error_contains """
  (var payload `(payload ^a 1 ^extra 9 2))
  (var [^a b] payload)
""", [
  "Destructuring pattern mismatch",
  "Unexpected keyword argument: extra",
]

test_vm_error_contains """
  (var payload `(payload ^a 1))
  (var [^a b] payload)
""", [
  "Destructuring pattern mismatch",
  "Expected 2 arguments, got 0",
]

test_vm_error_contains """
  (var [... tail] [1 2])
""", [
  "Positional rest must follow a named parameter",
]

# duplicate positional rest is rejected
test_vm_error_contains """
  (var [a... b...] [1 2 3])
""", [
  "Only one named positional rest parameter is allowed",
]

test_vm_error_contains """
  (match 1 when 1 2)
""", [
  "match has been removed",
  "(var pattern value)",
  "(case ...)",
]

# explicit nil default in destructuring stays NIL
test_vm """
  (var [value = nil] [])
  value
""", NIL

# proc test_arg_matching*(pattern: string, input: string, callback: proc(result: MatchResult)) =
#   var pattern = cleanup(pattern)
#   var input = cleanup(input)
#   test "Pattern Matching: \n" & pattern & "\n" & input:
#     var p = read(pattern)
#     var i = read(input)
#     var m = new_arg_matcher()
#     m.parse(p)
#     var result = m.match(i)
#     callback(result)

# test_arg_matching "a", "[1]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 1
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1

# test_arg_matching "_", "[]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 0

# test_arg_matching "a", "[]", proc(r: MatchResult) =
#   check r.kind == MatchMissingFields
#   check r.missing[0] == "a"

# test_arg_matching "a", "(_ 1)", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 1
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1

# test_arg_matching "[a b]", "[1 2]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 2
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1
#   check r.fields[1].name == "b"
#   check r.fields[1].value == 2

# test_arg_matching "[_ b]", "(_ 1 2)", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 1
#   check r.fields[0].name == "b"
#   check r.fields[0].value == 2

# test_arg_matching "[[a] b]", "[[1] 2]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 2
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1
#   check r.fields[1].name == "b"
#   check r.fields[1].value == 2

# test_arg_matching "[[[a] [b]] c]", "[[[1] [2]] 3]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 3
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1
#   check r.fields[1].name == "b"
#   check r.fields[1].value == 2
#   check r.fields[2].name == "c"
#   check r.fields[2].value == 3

# test_arg_matching "[a = 1]", "[]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 1
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1

# test_arg_matching "[a b = 2]", "[1]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 2
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1
#   check r.fields[1].name == "b"
#   check r.fields[1].value == 2

# test_arg_matching "[a = 1 b]", "[2]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 2
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1
#   check r.fields[1].name == "b"
#   check r.fields[1].value == 2

# test_arg_matching "[a b = 2 c]", "[1 3]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 3
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1
#   check r.fields[1].name == "b"
#   check r.fields[1].value == 2
#   check r.fields[2].name == "c"
#   check r.fields[2].value == 3

# test_arg_matching "[a...]", "[1 2]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 1
#   check r.fields[0].name == "a"
#   check r.fields[0].value == new_gene_vec(new_gene_int(1), new_gene_int(2))

# test_arg_matching "[a b...]", "[1 2 3]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 2
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1
#   check r.fields[1].name == "b"
#   check r.fields[1].value == new_gene_vec(new_gene_int(2), new_gene_int(3))

# test_arg_matching "[a... b]", "[1 2 3]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 2
#   check r.fields[0].name == "a"
#   check r.fields[0].value == new_gene_vec(new_gene_int(1), new_gene_int(2))
#   check r.fields[1].name == "b"
#   check r.fields[1].value == 3

# test_arg_matching "[a b... c]", "[1 2 3 4]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 3
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1
#   check r.fields[1].name == "b"
#   check r.fields[1].value == new_gene_vec(new_gene_int(2), new_gene_int(3))
#   check r.fields[2].name == "c"
#   check r.fields[2].value == 4

# test_arg_matching "[a [b... c]]", "[1 [2 3 4]]", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 3
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1
#   check r.fields[1].name == "b"
#   check r.fields[1].value == new_gene_vec(new_gene_int(2), new_gene_int(3))
#   check r.fields[2].name == "c"
#   check r.fields[2].value == 4

# # test_arg_matching "[a :do b]", "[1 do 2]", proc(r: MatchResult) =
# #   check r.kind == MatchSuccess
# #   check r.fields.len == 2
# #   check r.fields[0].name == "a"
# #   check r.fields[0].value == 1
# #   check r.fields[1].name == "b"
# #   check r.fields[1].value == 2

# test_arg_matching "[^a]", "(_ ^a 1)", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 1
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1

# test_arg_matching "[^a = 1]", "(_)", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 1
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1

# test_arg_matching "[^a = 1 b]", "(_ 2)", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 2
#   check r.fields[0].name == "a"
#   check r.fields[0].value == 1
#   check r.fields[1].name == "b"
#   check r.fields[1].value == 2

# test_arg_matching "[^a]", "()", proc(r: MatchResult) =
#   check r.kind == MatchMissingFields
#   check r.missing[0] == "a"

# test_arg_matching "[^props...]", "(_ ^a 1 ^b 2)", proc(r: MatchResult) =
#   check r.kind == MatchSuccess
#   check r.fields.len == 1
#   check r.fields[0].name == "props"
#   check r.fields[0].value.map["a"] == 1
#   check r.fields[0].value.map["b"] == 2
