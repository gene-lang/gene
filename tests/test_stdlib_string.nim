import unittest
import ./helpers
import gene/types except Exception

test_vm """
  (("" .class).name)
""", "String"

test_vm """
  ("abc" .size)
""", 3

test_vm """
  ("abc" .substr 1)
""", "bc"

test_vm """
  ("abc" .substr -1)
""", "c"

test_vm """
  ("abc" .substr -2 -1)
""", "bc"

test_vm """
  ("a:b:c" .split ":")
""", proc(result: Value) =
  check result.kind == VkArray
  check array_data(result).len == 3
  check array_data(result)[0].str == "a"
  check array_data(result)[1].str == "b"
  check array_data(result)[2].str == "c"

test_vm """
  ("a:b:c" .split ":" 2)
""", proc(result: Value) =
  check result.kind == VkArray
  check array_data(result).len == 2
  check array_data(result)[0].str == "a"
  check array_data(result)[1].str == "b:c"

test_vm """
  ("abc" .index "b")
""", 1

test_vm """
  ("abc" .index "x")
""", -1

test_vm """
  ("aba" .rindex "a")
""", 2

test_vm """
  ("abc" .rindex "x")
""", -1

test_vm """
  ("  abc  " .trim)
""", "abc"

test_vm """
  ("abc" .starts_with "ab")
""", true

test_vm """
  ("abc" .starts_with "bc")
""", false

test_vm """
  ("abc" .ends_with "ab")
""", false

test_vm """
  ("abc" .ends_with "bc")
""", true

test_vm """
  ("abc" .to_uppercase)
""", "ABC"

test_vm """
  ("ABC" .to_uppercase)
""", "ABC"

test_vm """
  ("abc" .to_lowercase)
""", "abc"

test_vm """
  ("ABC" .to_lowercase)
""", "abc"

test_vm """
  ("42" .to_i)
""", 42

test_vm """
  ("  -7  " .to_i)
""", -7

test_vm_error """
  ("abc" .to_i)
"""

test_vm """
  ("abc" .char_at 1)
""", 'b'

test_vm """
  ($ "a" "b" 1)
""", "ab1"

test_vm """
  (var b "c")
  (#Str "a" b)
""", "ac"

test_vm """
  (var b "c")
  #"a#{b}"
""", "ac"

test_vm """
  (var s "a")
  (s .append "b")
  (s .append "c")
  s
""", "abc"

test_vm """
  ("aabc" .replace "a" "A")
""", "Aabc"
