import unittest
import gene/types except Exception
import gene/parser
import gene/compiler
import gene/vm

suite "VM IkNeg tests":
  test "Unary minus on positive integer":
    let parsed = read("(- 5)")
    let cu = compile(@[parsed])
    var vm = VirtualMachine(cu: cu, frame: new_frame())
    let result = vm.exec()
    
    check result.kind == VkInt
    check result.int64 == -5
    
  test "Unary minus on negative integer":
    let parsed = read("(- -10)")
    let cu = compile(@[parsed])
    var vm = VirtualMachine(cu: cu, frame: new_frame())
    let result = vm.exec()
    
    check result.kind == VkInt
    check result.int64 == 10
    
  test "Unary minus on float":
    let parsed = read("(- 5.5)")
    let cu = compile(@[parsed])
    var vm = VirtualMachine(cu: cu, frame: new_frame())
    let result = vm.exec()
    
    check result.kind == VkFloat
    check result.float == -5.5
    
  test "Unary minus on zero":
    let parsed = read("(- 0)")
    let cu = compile(@[parsed])
    var vm = VirtualMachine(cu: cu, frame: new_frame())
    let result = vm.exec()
    
    check result.kind == VkInt
    check result.int64 == 0