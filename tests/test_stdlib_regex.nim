import ./helpers
import gene/types except Exception

test_vm """
  (#/a/ .match "a")
""", TRUE

test_vm """
  (var r (new gene/Regexp ^^i "ab"))
  (r .match "AB")
""", TRUE

test_vm """
  (var m (#/(a)(b)/ .process "ab"))
  m/captures/0
""", "a"

test_vm """
  (#/(\\d)/[\\1]/ .replace_all "a1b2")
""", "a[1]b[2]"

test_vm """
  ("a1b2" .replace_all #/(\\d)/[\\1]/)
""", "a[1]b[2]"

test_vm_error """
  ("ab" .match "a")
"""
