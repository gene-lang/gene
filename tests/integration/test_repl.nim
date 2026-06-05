import unittest, strutils, tables

import ../helpers

import gene/compiler
import gene/types except Exception
import gene/vm
import gene/repl_session
import gene/repl_input

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

  test "renders return values with prompt marker":
    check render_repl_result(NIL) == "=> nil"
    check render_repl_result(VOID) == "=> void"
    check render_repl_result(1.to_value()) == "=> 1"
    check render_repl_result("haha".to_value()) == "=> \"haha\""

  test "renders functions by name and argument presence":
    let ns = new_namespace(App.app.global_ns.ref.ns, "repl")
    let scope_tracker = new_scope_tracker()
    let scope = new_scope(scope_tracker)
    var rendered: seq[string] = @[]

    proc collect(value: Value) =
      rendered.add(render_repl_result(value))

    discard run_repl_script(VM, @[
      "(fn f [] 1) (fn g [x] x) (fn [] 1) (fn [x] x)"
    ], scope_tracker, scope, ns, on_result = collect)

    check rendered == @[
      "=> (fn f [])",
      "=> (fn g [...])",
      "=> (fn [])",
      "=> (fn [...])",
    ]

  test "reports every top-level form from one submitted input":
    let ns = new_namespace(App.app.global_ns.ref.ns, "repl")
    let scope_tracker = new_scope_tracker()
    let scope = new_scope(scope_tracker)
    var rendered: seq[string] = @[]

    proc collect(value: Value) =
      rendered.add(render_repl_result(value))

    let result = run_repl_script(VM, @["1 2 (+ 1 2)"], scope_tracker, scope, ns,
                                 on_result = collect)

    check result == 3.to_value()
    check rendered == @["=> 1", "=> 2", "=> 3"]

  test "stops after parse failure and reports full input line":
    let ns = new_namespace(App.app.global_ns.ref.ns, "repl")
    let scope_tracker = new_scope_tracker()
    let scope = new_scope(scope_tracker)
    var rendered: seq[string] = @[]
    var failed = false

    proc collect(value: Value) =
      rendered.add(render_repl_result(value))

    try:
      discard run_repl_script(VM, @["1\n2\n] 3"], scope_tracker, scope, ns,
                              "multi_repl.gene", on_result = collect)
    except CatchableError as e:
      failed = true
      check e.msg.contains("multi_repl.gene:3:")

    check failed
    check rendered == @["=> 1", "=> 2"]

  test "stops after execution failure before later forms":
    let ns = new_namespace(App.app.global_ns.ref.ns, "repl")
    let scope_tracker = new_scope_tracker()
    let scope = new_scope(scope_tracker)
    var failed = false

    try:
      discard run_repl_script(VM, @["(var x 1) (+ 1 \"x\") (x = 3)"], scope_tracker, scope, ns)
    except CatchableError:
      failed = true
      VM.current_exception = NIL

    check failed
    check run_repl_script(VM, @["x"], scope_tracker, scope, ns) == 1.to_value()

  test "history suppresses immediate duplicates and blanks":
    check should_record_repl_history_entry("", "") == false
    check should_record_repl_history_entry("x", "") == true
    check should_record_repl_history_entry("x", "x") == false
    check should_record_repl_history_entry("(+ x 1)", "x") == true

  test "readline backend only activates for tty sessions with backend":
    check should_use_readline_backend(true, true) == true
    check should_use_readline_backend(true, false) == false
    check should_use_readline_backend(false, true) == false
