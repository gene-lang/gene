import gene/types except Exception

import ./helpers

# Cast an object of one type to another, with optional behavior overwriting
# Typical use: (cast (new A) B ...)

# TODO: cast is not implemented in the VM yet
# test_vm """
#   (class A
#     (.fn test _
#       1
#     )
#   )
#   (class B
#     (.fn test _
#       2
#     )
#   )
#   ((cast (new A) B).test)
# """, 2
