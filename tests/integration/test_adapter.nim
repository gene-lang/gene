import unittest
import ../helpers

suite "adapter runtime":
  test_vm """
    (do
      (interface B (method b []))
      (interface A (method a []))
      (class C
        (ctor [] nil)
        (method a [] "A")
        (method b [] "B")
      )
      (implement A for C)
      (implement B for C)
      ((B (A (new C))) .b)
    )
  """, "B"

  test_vm """
    (do
      (interface Ageable
        (method age [] -> Int)
      )
      (implement Ageable for Int
        (ctor [birth_year]
          (/_geneinternal/birth_year = birth_year)
        )
        (method age []
          (/_genevalue - /_geneinternal/birth_year)
        )
      )
      ((Ageable 2026 1990) .age)
    )
  """, 36

  test_vm """
    (do
      (interface Sized (method length []))
      (implement Sized for String)
      ((Sized "abc") .length)
    )
  """, 3

  test_vm """
    (do
      (interface Readable (method read []))
      (class C
        (ctor [] (/x = 1))
      )
      (implement Readable for C
        (method read [] /_genevalue/x)
      )
      (var r (Readable (new C)))
      (var m r/read)
      (m)
    )
  """, 1

  test_vm_error """
    (do
      (interface View)
      (class C (ctor [] nil))
      (implement View for C)
      (var v (View (new C)))
      (v/secret = 1)
    )
  """
