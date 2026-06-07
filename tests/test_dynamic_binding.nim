import os, strutils, unittest

import ../src/gene/types except Exception
import ../src/gene/vm

proc fixture_ext(): string =
  when defined(macosx):
    ".dylib"
  elif defined(linux):
    ".so"
  else:
    ".dll"

proc fixture_base_path(): string =
  for base in @["dyn_binding_fixture", "tests/dyn_binding_fixture"]:
    if fileExists(base & fixture_ext()):
      return base
  "tests/dyn_binding_fixture"

proc fixture_file_path(): string =
  fixture_base_path() & fixture_ext()

proc build_fixture(): bool =
  let output = "dyn_binding_fixture" & fixture_ext()
  when defined(macosx):
    let cmd = "cd tests && ${CC:-cc} -dynamiclib -fPIC -O2 -Wall -o " &
      output & " dyn_binding.c"
  elif defined(linux):
    let cmd = "cd tests && ${CC:-cc} -shared -fPIC -O2 -Wall -o " &
      output & " dyn_binding.c"
  else:
    let cmd = "cd tests && ${CC:-cc} -shared -O2 -Wall -o " &
      output & " dyn_binding.c"
  execShellCmd(cmd) == 0 and fileExists(fixture_file_path())

proc gene_string_literal(s: string): string =
  "\"" & s.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

proc dyn_find(symbol: string): string =
  "($dyn/find ($dyn/load " & gene_string_literal(fixture_base_path()) & ") " &
    gene_string_literal(symbol) & ")"

proc exec_dyn(code: string): Value =
  VM.exec(code, "dynamic_binding_test.gene")

proc expect_error(action: proc() {.closure.}): string =
  try:
    action()
    fail()
  except CatchableError as e:
    result = e.msg

suite "Dynamic Library Binding":
  setup:
    init_app_and_vm()
    init_stdlib()
    if not build_fixture():
      skip()

  test "$dyn/load and ^native bind Int, Bool, and String cdecl functions":
    let dyn_add = exec_dyn("""
      (fn dyn-add [a: Int b: Int] -> Int
        ^native """ & dyn_find("gene_dyn_add") & """
        ^abi "cdecl")
      dyn-add
    """)
    check dyn_add.kind == VkNativeFn
    check dyn_add.ref.native_binding != nil
    check dyn_add.ref.native_binding.sig != nil
    check dyn_add.ref.native_binding.sig.abi == "cdecl"
    check lookup_native_signature(dyn_add.ref.native_fn) == nil
    check native_signature_for_native_value(dyn_add) != nil

    check exec_dyn("""
      (fn dyn-add [a: Int b: Int] -> Int
        ^native """ & dyn_find("gene_dyn_add") & """
        ^abi "cdecl")
      (dyn-add 20 22)
    """).to_int() == 42

    check exec_dyn("""
      (fn dyn-even [n: Int] -> Bool
        ^native """ & dyn_find("gene_dyn_is_even") & """)
      (dyn-even 24)
    """) == TRUE

    check exec_dyn("""
      (fn dyn-strlen [s: String] -> Int
        ^native """ & dyn_find("gene_dyn_strlen") & """
        ^abi "cdecl")
      (dyn-strlen "hello")
    """).to_int() == 5

    let greeting = exec_dyn("""
      (fn dyn-greet [name: String] -> String
        ^native """ & dyn_find("gene_dyn_greet") & """
        ^abi "cdecl")
      (dyn-greet "Gene")
    """)
    check greeting.kind == VkString
    check greeting.str == "hello, Gene"

  test "$dyn/load handle can be reused from a variable":
    check exec_dyn("""
      (var lib ($dyn/load """ & gene_string_literal(fixture_base_path()) & """))
      (fn dyn-add [a: Int b: Int] -> Int
        ^native ($dyn/find lib "gene_dyn_add")
        ^abi "cdecl")
      (dyn-add 9 33)
    """).to_int() == 42

  test "dynamic cdecl bindings marshal Void and Pointer":
    let result = exec_dyn("""
      (fn dyn-set-last [value: Int] -> Void
        ^native """ & dyn_find("gene_dyn_set_last") & """
        ^abi "cdecl")
      (fn dyn-get-last [] -> Int
        ^native """ & dyn_find("gene_dyn_get_last") & """
        ^abi "cdecl")
      (dyn-set-last 99)
      (dyn-get-last)
    """)
    check result.to_int() == 99

    let pointer_round_trip = exec_dyn("""
      (fn dyn-static-ptr [] -> Pointer
        ^native """ & dyn_find("gene_dyn_static_ptr") & """
        ^abi "cdecl")
      (fn dyn-identity-ptr [p: Pointer] -> Pointer
        ^native """ & dyn_find("gene_dyn_identity_ptr") & """
        ^abi "cdecl")
      ((dyn-identity-ptr (dyn-static-ptr)) == (dyn-static-ptr))
    """)
    check pointer_round_trip == TRUE

  test "dynamic cdecl constructors wrap Pointer returns for methods":
    let method_result = exec_dyn("""
      (class DynHandle
        (ctor [] -> Pointer
          ^native """ & dyn_find("gene_dyn_static_ptr") & """
          ^abi "cdecl")
        (method identity [] -> Pointer
          ^native """ & dyn_find("gene_dyn_identity_ptr") & """
          ^abi "cdecl"))
      (var handle (new DynHandle))
      ((handle .identity) == handle)
    """)
    check method_result == TRUE

  test "$dyn/find reports symbol and library on missing symbol":
    let message = expect_error(proc() =
      discard exec_dyn("""
        (fn dyn-missing [] -> Int
          ^native """ & dyn_find("gene_dyn_missing") & """
          ^abi "cdecl")
        (dyn-missing)
      """)
    )
    check message.contains("gene_dyn_missing")
    check message.contains("dyn_binding_fixture")

  test "dynamic cdecl rejects unsupported Float declarations":
    let message = expect_error(proc() =
      discard exec_dyn("""
        (fn dyn-float [n: Float] -> Int
          ^native """ & dyn_find("gene_dyn_add") & """
          ^abi "cdecl")
      """)
    )
    check message.contains("Float") or message.contains("unsupported")
