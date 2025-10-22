import unittest
import std/times
import ./helpers
import gene/types

test_vm """
  ((gene/today) .year)
""", now().year

test_vm """
  ((gene/now) .year)
""", now().year
