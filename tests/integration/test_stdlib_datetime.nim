import unittest
import std/times
import ../helpers
import gene/types except Exception

test_vm """
  ((gene/today) .year)
""", now().year

test_vm """
  ((gene/now) .year)
""", now().year

test_vm """
  (2024-01-23T20:10:10.123456Z .microsecond)
""", 123456

test_vm """
  (2024-01-23T20:10:10.123456Z .to_i)
""", 1706040610123'i64
