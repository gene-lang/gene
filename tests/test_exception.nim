import gene/types except Exception

import ./helpers

# NOTE: Exception handling is not yet implemented in the VM
# All tests below use test_interpreter which is not defined
# Basic VM throw test (merged from test_vm_exception.nim)
test_vm_error """
  (throw "test error")
"""

# These tests serve as documentation for future implementation

# Native Nim exception vs Gene exception:
# Nim exceptions can be accessed from nim/ namespace
# Nim exceptions should be translated to Gene exceptions eventually
# Gene core exceptions are defined in gene/ namespace
# Gene exceptions share same Nim class: GeneException
# For convenience purpose all exception classes like gene/XyzException are aliased as XyzException

# Retry support - from the beginning of try?
# (try...catch...(retry))

# (throw)
# (throw message)
# (throw Exception)
# (throw Exception message)
# (throw (new Exception ...))

# (try...catch...catch...finally)
# (try...finally)
# (fn f []  # converted to (try ...)
#   ...
#   catch ExceptionX ...
#   catch * ...
#   finally ...
# )

# test "(throw ...)":
#   var code = """
#     (throw "test")
#   """.cleanup
#   test "Interpreter / eval: " & code:
#     init_all()
#     discard VM.eval(code)
#     # try:
#     #   discard VM.eval(code)
#     #   check false
#     # except:
#     #   discard

# Exception handling is not yet implemented in the VM
# These tests are placeholders for future implementation
test_vm """
  (try
    (throw)
    1
  catch *
    2
  )
""", 2

# TODO: Enable these tests once class inheritance and exception type matching are implemented
# test_vm """
#   (class TestException < GeneException)
#   (try
#     (throw TestException)
#     1
#   catch TestException
#     2
#   catch *
#     3
#   )
# """, 2

# test_vm """
#   (class TestException < GeneException)
#   (try
#     (throw)
#     1
#   catch TestException
#     2
#   catch *
#     3
#   )
# """, 3

test_vm """
  (try
    (throw "test")
  catch *
    $ex
  )
""", "test"

test_vm """
  (try
    (throw)
    1
  catch *
    2
  finally
    3   # value is discarded
  )
""", 2

# # Try can be omitted on the module level, like function body
# # This can simplify freeing resources
# test_vm """
#   (throw)
#   1
#   catch *
#   2
#   finally
#   3
# """, 2

# test_vm """
#   1
#   finally
#   3
# """, 1

test_vm """
  (try
    (throw)
    1
  catch *
    2
  finally
    (return 3)  # not allowed
  )
""", 2

test_vm """
  (try
    (throw)
    1
  catch *
    2
  finally
    (break)  # not allowed
  )
""", 2

test_vm """
  (var a 0)
  (try
    (throw)
    (a = 1)
  catch *
    (a = 2)
  finally
    (a = 3)
  )
  a
""", 3


# test_vm """
#   (fn f _
#     (throw)
#     1
#   catch *
#     2
#   finally
#     3
#   )
#   (f)
# """, 2

# test_vm """
#   (macro m _
#     (throw)
#     1
#   catch *
#     2
#   finally
#     3
#   )
#   (m)
# """, 2

# test_vm """
#   (fn f blk
#     (blk)
#   )
#   (f
#     (->
#       (throw)
#       1
#     catch *
#       2
#     finally
#       3
#     )
#   )
# """, 2

# test_vm """
#   (do
#     (throw)
#     1
#   catch *
#     2
#   finally
#     3
#   )
# """, 2
