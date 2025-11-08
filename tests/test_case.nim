import gene/types except Exception

import ./helpers

# Tests for case/match construct
# Most case functionality is not yet implemented in our VM
# These tests are commented out until those features are available:

# test_vm """
#   (case 1
#     1 "one"
#     2 "two"
#   )
# """, "one"

# test_vm """
#   (case 2
#     1 "one"
#     2 "two"
#     else "other"
#   )
# """, "two"

# Placeholder test for now
test_vm "1", 1