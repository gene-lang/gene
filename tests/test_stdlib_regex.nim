import ./helpers
import gene/types except Exception

test_vm """
  (regex_match "a" (regex_create "a"))
""", TRUE

test_vm """
  (regex_match "a" (regex_create "b"))
""", FALSE

test_vm """
  (regex_find "a" (regex_create "(a)"))
""", "a"

test_vm """
  (regex_find "ab" (regex_create "(a)(b)" false true) 2)
""", "b"

test_vm """
  (regex_match "AB" (regex_create "(ab)" true))
""", TRUE
