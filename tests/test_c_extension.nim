import unittest
import os

import gene/types except Exception
import gene/compiler
import gene/vm
import gene/vm/extension
from gene/parser import read

# Import C API to ensure it's linked
import gene/extension/c_api

# Export symbols for dynamic loading on macOS
{.passL: "-Wl,-export_dynamic".}

suite "C Extension Support":
  setup:
    init_app_and_vm()
    init_stdlib()
    
    # Build C extension if not already built
    let ext_path = "tests/c_extension"
    when defined(macosx):
      let ext_file = ext_path & ".dylib"
    elif defined(linux):
      let ext_file = ext_path & ".so"
    else:
      let ext_file = ext_path & ".dll"
    
    if not fileExists(ext_file):
      echo "Building C extension..."
      discard execShellCmd("cd tests && make -f Makefile.c_extension")
    
    # Load the C extension
    if fileExists(ext_file):
      # Use absolute path for loading
      let abs_path = getCurrentDir() / ext_path
      let c_ext_ns = VM.load_extension(abs_path)
      App.app.global_ns.ref.ns["c_ext".to_key()] = c_ext_ns.to_value()
    else:
      echo "WARNING: C extension not found at: ", ext_file
      echo "Run: nimble buildcext"

  test "C extension - add function":
    let code = "(c_ext/add 10 20)"
    let ast = read(code)
    let cu = compile_init(ast)
    
    VM.cu = cu
    VM.pc = 0
    VM.frame = new_frame()
    VM.frame.stack_index = 0
    VM.frame.scope = new_scope(new_scope_tracker())
    VM.frame.ns = App.app.gene_ns.ref.ns
    
    let result = VM.exec()
    check to_int(result) == 30

  test "C extension - multiply function":
    let code = "(c_ext/multiply 6 7)"
    let ast = read(code)
    let cu = compile_init(ast)
    
    VM.cu = cu
    VM.pc = 0
    VM.frame = new_frame()
    VM.frame.stack_index = 0
    VM.frame.scope = new_scope(new_scope_tracker())
    VM.frame.ns = App.app.gene_ns.ref.ns
    
    let result = VM.exec()
    check to_int(result) == 42

  test "C extension - concat function":
    let code = """(c_ext/concat "Hello, " "World!")"""
    let ast = read(code)
    let cu = compile_init(ast)
    
    VM.cu = cu
    VM.pc = 0
    VM.frame = new_frame()
    VM.frame.stack_index = 0
    VM.frame.scope = new_scope(new_scope_tracker())
    VM.frame.ns = App.app.gene_ns.ref.ns
    
    let result = VM.exec()
    check result.str == "Hello, World!"

  test "C extension - strlen function":
    let code = """(c_ext/strlen "Hello")"""
    let ast = read(code)
    let cu = compile_init(ast)
    
    VM.cu = cu
    VM.pc = 0
    VM.frame = new_frame()
    VM.frame.stack_index = 0
    VM.frame.scope = new_scope(new_scope_tracker())
    VM.frame.ns = App.app.gene_ns.ref.ns
    
    let result = VM.exec()
    check to_int(result) == 5

  test "C extension - is_even function":
    let code1 = "(c_ext/is_even 4)"
    let ast1 = read(code1)
    let cu1 = compile_init(ast1)
    
    VM.cu = cu1
    VM.pc = 0
    VM.frame = new_frame()
    VM.frame.stack_index = 0
    VM.frame.scope = new_scope(new_scope_tracker())
    VM.frame.ns = App.app.gene_ns.ref.ns
    
    let result1 = VM.exec()
    check result1 == TRUE
    
    let code2 = "(c_ext/is_even 5)"
    let ast2 = read(code2)
    let cu2 = compile_init(ast2)
    
    VM.cu = cu2
    VM.pc = 0
    VM.frame = new_frame()
    VM.frame.stack_index = 0
    VM.frame.scope = new_scope(new_scope_tracker())
    VM.frame.ns = App.app.gene_ns.ref.ns
    
    let result2 = VM.exec()
    check result2 == FALSE

  test "C extension - greet function":
    let code = """(c_ext/greet "Alice")"""
    let ast = read(code)
    let cu = compile_init(ast)
    
    VM.cu = cu
    VM.pc = 0
    VM.frame = new_frame()
    VM.frame.stack_index = 0
    VM.frame.scope = new_scope(new_scope_tracker())
    VM.frame.ns = App.app.gene_ns.ref.ns
    
    let result = VM.exec()
    check result.str == "Hello, Alice!"

