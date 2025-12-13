import unittest
import gene/types except Exception
import gene/parser
import gene/compiler
import gene/vm
import ./helpers

suite "VM IkNeg tests":
  init_all()

  test "Unary minus on positive integer":
    let parsed = read("(- 5)")
    let cu = compile(@[parsed])
    let vm = new_vm_ptr()
    let scope_tracker = new_scope_tracker()
    vm.frame = new_frame()
    vm.frame.stack_index = 0
    vm.frame.scope = new_scope(scope_tracker)
    vm.frame.ns = App.app.gene_ns.ref.ns
    vm.cu = cu
    vm.pc = 0
    let result = vm.exec()
    free_vm_ptr(vm)
    
    check result.kind == VkInt
    check result.int64 == -5
    
  test "Unary minus on negative integer":
    let parsed = read("(- -10)")
    let cu = compile(@[parsed])
    let vm = new_vm_ptr()
    let scope_tracker = new_scope_tracker()
    vm.frame = new_frame()
    vm.frame.stack_index = 0
    vm.frame.scope = new_scope(scope_tracker)
    vm.frame.ns = App.app.gene_ns.ref.ns
    vm.cu = cu
    vm.pc = 0
    let result = vm.exec()
    free_vm_ptr(vm)
    
    check result.kind == VkInt
    check result.int64 == 10
    
  test "Unary minus on float":
    let parsed = read("(- 5.5)")
    let cu = compile(@[parsed])
    let vm = new_vm_ptr()
    let scope_tracker = new_scope_tracker()
    vm.frame = new_frame()
    vm.frame.stack_index = 0
    vm.frame.scope = new_scope(scope_tracker)
    vm.frame.ns = App.app.gene_ns.ref.ns
    vm.cu = cu
    vm.pc = 0
    let result = vm.exec()
    free_vm_ptr(vm)
    
    check result.kind == VkFloat
    check result.float == -5.5
    
  test "Unary minus on zero":
    let parsed = read("(- 0)")
    let cu = compile(@[parsed])
    let vm = new_vm_ptr()
    let scope_tracker = new_scope_tracker()
    vm.frame = new_frame()
    vm.frame.stack_index = 0
    vm.frame.scope = new_scope(scope_tracker)
    vm.frame.ns = App.app.gene_ns.ref.ns
    vm.cu = cu
    vm.pc = 0
    let result = vm.exec()
    free_vm_ptr(vm)
    
    check result.kind == VkInt
    check result.int64 == 0
