import tables
import unittest

import gene/types except Exception

import ./helpers

test_serdes """
  1
""", 1

test_serdes """
  "abc"
""", "abc"

test_serdes """
  [1 2]
""", @[1, 2]

test_serdes """
  {^a 1}
""", new_map_value({"a".to_key(): new_gene_int(1)}.to_table())

test_serdes """
  (:a ^a 2 3 4)
""", proc(r: Value) =
  check r.gene_type == new_gene_symbol("a")
  check r.gene_props == {"a": new_gene_int(2)}.toTable
  check r.gene_children == @[3.to_value(), 4.to_value()]

test_vm """
  (class A)
  (var x (gene/serdes/serialize A))
  (var A* (gene/serdes/deserialize x))
  A*/.name
""", "A"

test_vm """
  (class A)
  (var a (new A))
  (var x (gene/serdes/serialize a))
  (var a* (gene/serdes/deserialize x))
  a*/.class/.name
""", "A"

test_vm """
  (class A)
  (var a (new A))
  (a/test = 1)
  (var x (gene/serdes/serialize a))
  (var a* (gene/serdes/deserialize x))
  a*/test
""", 1

test_vm """
  (fn f _ 1)
  (var x (gene/serdes/serialize f))
  (var f* (gene/serdes/deserialize x))
  (f*)
""", 1

# test_vm """
#   (var f (fnx _ 1))
#   (gene/serdes/ref "f" f) # Will add f to a global map like "<pkg>:<module>:_serdes/f" => f
#   (var x (gene/serdes/serialize f))
#   (var f* (gene/serdes/deserialize x))
#   (f*)
# """, 1

# TODO: Fix namespace path resolution for functions in namespaces
# test_vm """
#   (ns n
#     (fn f _ 1)
#   )
#   (var x (gene/serdes/serialize n/f))
#   (var f* (gene/serdes/deserialize x))
#   (f*)
# """, 1
