import unittest
import os

import gene/types except Exception
import gene/parser
import gene/compiler
import gene/vm

import ./helpers

proc test_extension(code: string, result: Value) =
  var code = cleanup(code)
  test "VM / Extension: " & code:
    let parsed = read_all(code)
    let compiled = compile(parsed)
    
    # Use global VM
    let saved_cu = VM.cu
    let saved_frame = VM.frame
    
    VM.cu = compiled
    let actual = VM.exec()
    
    # Restore state
    VM.cu = saved_cu
    VM.frame = saved_frame
    
    check actual == result

suite "Extension":
  # Build test extensions first
  # Check if we're in tests directory or root
  if fileExists("build_extensions.sh"):
    discard execShellCmd("./build_extensions.sh")
  else:
    discard execShellCmd("cd tests && ./build_extensions.sh")
  
  # Initialize the app and VM
  init_app_and_vm()
  
  # Create a test namespace and set it as current
  let test_ns = new_namespace("test")
  VM.frame = new_frame()
  VM.frame.ns = test_ns
  # Self is no longer stored in frame - it's passed as an argument
  # For namespace initialization, we pass it as args
  let ns_value = new_ref(VkNamespace).to_ref_value()
  ns_value.ref.ns = test_ns
  let args_gene = new_gene(NIL)
  args_gene.children.add(ns_value)
  VM.frame.args = args_gene.to_gene_value()
  
  # Setup initial imports - handle both running from root and tests directory
  let ext_path = if fileExists("extension.dylib") or fileExists("extension.so") or fileExists("extension.dll"):
    ""
  else:
    "tests/"
    
  discard VM.exec("""
    (import test new_extension get_i from """" & ext_path & """extension" ^^native)
    (import new_extension2 extension2_name from """" & ext_path & """extension2" ^^native)
  """, "test")

  test_extension """
    (test 1)
  """, 1.to_value()

  test_extension """
    (test (extension2_name (new_extension2 "x")))
  """, "x".to_value()

  test_extension """
    (get_i (new_extension 1 "s"))
  """, 1.to_value()

  # Note: Class-based tests are skipped as VM doesn't support full OOP yet
  # test_extension """
  #   (((new_extension 1 "s") .class) .name)
  # """, "Extension"

  # test_extension """
  #   ((new_extension 1 "s") .i)
  # """, 1

  # test_extension """
  #   ((new Extension 1 "s") .i)
  # """, 1

  # test_extension """
  #   Extension/.name
  # """, "Extension"

  # Exception handling test - simpler version first
  test "VM / Extension: exception in test function":
    # This tests if exceptions thrown in extensions are properly caught
    skip()
