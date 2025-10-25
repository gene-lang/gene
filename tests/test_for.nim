import gene/types except Exception

import ./helpers

# Tests for for loop construct
# Most for functionality is not yet implemented in our VM
# These tests are commented out until those features are available:

test_vm """
  (var sum 0)
  (for i in [1 2 3]
    (sum += i)
  )
  sum
""", 6

test_vm """
  (var sum 0)
  (for i in (0 .. 2)
    (sum += i)
  )
  sum
""", 3
