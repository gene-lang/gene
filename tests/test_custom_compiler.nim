import gene/types

import ./helpers  # Ensure helpers is used

# Custom compiler

# When a custom compiler is called, code is first compiled then executed automatically
# Q: How are arguments processed?
# A:
# Q: Should compilation output be cached?
# A: Yes. Each compilation call should be executed once, then cached.
# Custom compiler vs function vs macro

# Custom instruction

# Has to be highly efficient
# Can only be implemented in Nim, e.g.
# define_instruction "DoX", proc(self: var Frame, inst: Instruction) =
#   ...

test_vm """
  (compile c _
    [
      ($vm/PUSH 1)
      ($vm/PUSH 2)
      ($vm/ADD)
    ]
  )
  (c)
""", 3

test_vm """
  (compile c _
    (var a 1)
    [
      ($vm/PUSH a)
      ($vm/PUSH 2)
      ($vm/ADD)
    ]
  )
  (c)
""", 3

test_vm """
  (compile c a
    [
      ($vm/PUSH a)
      ($vm/PUSH 2)
      ($vm/ADD)
    ]
  )
  (c 1)
""", 3

test_vm """
  (compile c a
    [
      ($vm/compile a)
      ($vm/PUSH 2)
      ($vm/ADD)
    ]
  )
  (var b 1)
  (c b)
""", 3

test_vm """
  (compile c a
    [
      ($vm/compile a)
      ($vm/PUSH 2)
      ($vm/ADD)
    ]
  )
  (fn f x
    (c x)
  )
  (f 1)
  (f 2)
""", 4
