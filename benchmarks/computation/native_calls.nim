when isMainModule:
  import times, os, strformat, strutils

  import ../../src/gene/types

  var iterations = 1_000_000
  let args = command_line_params()
  if args.len > 0:
    iterations = parseInt(args[0])

  proc native_f(vm: VirtualMachine, geneArgs: Value): Value {.gcsafe, nimcall.}

  proc native_f(vm: VirtualMachine, geneArgs: Value): Value {.gcsafe, nimcall.} =
    if geneArgs.kind != VkGene or geneArgs.gene.children.len < 2:
      return 0.to_value()

    let fn_val = geneArgs.gene.children[0]
    var n = geneArgs.gene.children[1].to_int()

    if n <= 0:
      return 0.to_value()

    n.dec()

    if fn_val.kind == VkNativeFn:
      let args_gene = new_gene(NIL)
      args_gene.children.add(fn_val)
      args_gene.children.add(n.to_value())
      return fn_val.ref.native_fn(vm, args_gene.to_gene_value())
    else:
      return n.to_value()

  init_app_and_vm()

  App.app.gene_ns.ns["native_f".to_key()] = native_f

  let native_val = App.app.gene_ns.ns["native_f".to_key()]
  doAssert native_val.kind == VkNativeFn

  proc callNative(fn_val: Value, count: int) =
    if count <= 0:
      return
    let args_gene = new_gene(NIL)
    args_gene.children.add(fn_val)
    args_gene.children.add(count.to_value())
    discard fn_val.ref.native_fn(VM, args_gene.to_gene_value())

  let start = cpuTime()
  let chunk = min(iterations, 1000)
  let loops = iterations div chunk
  let remainder = iterations mod chunk

  for _ in 0..<loops:
    callNative(native_val, chunk)
  callNative(native_val, remainder)
  let duration = cpuTime() - start

  let calls_per_second = if duration > 0: iterations.float / duration else: 0.0

  echo fmt"Iterations: {iterations}"
  echo fmt"Duration: {duration:.6f} seconds"
  echo fmt"Native calls/sec: {calls_per_second:.0f}"
