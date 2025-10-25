import unittest

import gene/types except Exception

import ./helpers

test_parser """
  #"abc"
""", "abc"

test_parser """
  #"a#{b}c"
""", proc(r: Value) =
  check r.gene.type == to_symbol_value("#Str")
  check r.gene.children[0] == "a"
  check r.gene.children[1] == to_symbol_value("b")
  check r.gene.children[2] == "c"

test_parser """
  #"a#(b)c"
""", proc(r: Value) =
  check r.gene.type == to_symbol_value("#Str")
  check r.gene.children[0] == "a"
  check r.gene.children[1].kind == VkGene
  check r.gene.children[1].gene.type == to_symbol_value("b")
  check r.gene.children[2] == "c"
