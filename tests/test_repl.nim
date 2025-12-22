import unittest, tables

import ./helpers
import ../src/gene/compiler
import ../src/gene/types except Exception
import ../src/gene/vm
import ../src/gene/repl_session

init_all()

suite "REPL":
  test "persistent scope across inputs":
    let ns = new_namespace(App.app.global_ns.ref.ns, "repl")
    let scope_tracker = new_scope_tracker()
    scope_tracker.scope_started = true
    let scope = new_scope(scope_tracker)

    var frame = new_frame(ns)
    frame.scope = scope
    VM.frame = frame

    proc eval_repl(code: string): Value =
      let cu = parse_and_compile_repl(code, "<repl>", scope_tracker)
      VM.frame = frame
      VM.cu = cu
      frame.stack_index = 0
      frame.call_bases.reset()
      VM.exec()

    discard eval_repl("(var x 1)")
    check eval_repl("x") == 1.to_value()

  test "parent scope access and update":
    let parent_tracker = new_scope_tracker()
    parent_tracker.scope_started = true
    parent_tracker.mappings["x".to_key()] = 0.int16
    parent_tracker.next_index = 1.int16

    let parent_scope = new_scope(parent_tracker)
    parent_scope.members.add(1.to_value())

    let repl_tracker = new_scope_tracker(parent_tracker)
    repl_tracker.scope_started = true
    let repl_scope = new_scope(repl_tracker, parent_scope)

    let ns = new_namespace(App.app.global_ns.ref.ns, "repl")
    var frame = new_frame(ns)
    frame.scope = repl_scope
    VM.frame = frame

    proc eval_repl(code: string): Value =
      let cu = parse_and_compile_repl(code, "<repl>", repl_tracker)
      VM.frame = frame
      VM.cu = cu
      frame.stack_index = 0
      frame.call_bases.reset()
      VM.exec()

    check eval_repl("x") == 1.to_value()
    discard eval_repl("(x = 2)")
    check parent_scope.members[0] == 2.to_value()

  test "returns last value from script":
    let ns = new_namespace(App.app.global_ns.ref.ns, "repl")
    let scope_tracker = new_scope_tracker()
    let scope = new_scope(scope_tracker)
    let result = run_repl_script(VM, @["(var x 1)", "(+ x 2)"], scope_tracker, scope, ns)
    check result == 3.to_value()
