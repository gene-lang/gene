import unittest
import ../src/gene/types except Exception

# Test basic functionality of extended type system
suite "Extended Type System":
  
  test "ValueKind enum completeness":
    # Test that we have all the expected value kinds
    check VkRatio.ord > VkInt.ord
    check VkRegex.ord > VkComplexSymbol.ord
    check VkDate.ord > VkTimezone.ord - 4  # Date comes before timezone
    check VkThread.ord >= VkFuture.ord
    check VkException.ord == 128  # Exceptions start at 128
  
  test "Value kind detection":
    let nil_val = NIL
    let bool_val = TRUE
    let int_val = 42.Value
    let float_val = 3.14.to_value()
    let str_val = "test".Value
    
    check nil_val.kind == VkNil
    check bool_val.kind == VkBool
    check int_val.kind == VkInt
    check float_val.kind == VkFloat
    check str_val.kind == VkString
  
  test "Value string representation":
    check $NIL == "nil"
    check $TRUE == "true"
    check $FALSE == "false"
    check $VOID == "void"
    check $PLACEHOLDER == "_"
    check $42.Value == "42"
    check $3.14.to_value() == "3.14"
  
  test "Value indexing and size":
    let arr = new_array_value(1.Value, 2.Value, 3.Value)
    check arr.size == 3
    check arr[0] == 1.Value
    check arr[1] == 2.Value
    check arr[2] == 3.Value
    check arr[3] == NIL  # Out of bounds returns NIL
  
  test "Complex symbol support":
    let parts = @["a", "b", "c"]
    let csym = to_complex_symbol(parts)
    check csym.kind == VkComplexSymbol
    check $csym == "a/b/c"
