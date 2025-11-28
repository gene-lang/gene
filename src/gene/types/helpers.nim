import os, times, tables

import ./type_defs
import ./value_core
import ./classes

proc refresh_env_map*()
proc set_program_args*(program: string, args: seq[string])

#################### VM ##########################

proc init_app_and_vm*() =
  # Reset gene namespace initialization flag since we're creating a new App
  gene_namespace_initialized = false

  # Initialize as main thread (ID 0)
  current_thread_id = 0

  VM = VirtualMachine(
    exception_handlers: @[],
    current_exception: NIL,
    symbols: addr SYMBOLS,
    pending_futures: @[],  # Initialize empty list of pending futures
    thread_futures: initTable[int, FutureObj](),  # Initialize empty table for thread futures
    message_callbacks: @[],  # Initialize empty list of message callbacks
    thread_local_ns: nil,  # Will be initialized after App is created
  )

  # Pre-allocate frame and scope pools
  if FRAMES.len == 0:
    FRAMES = newSeqOfCap[Frame](INITIAL_FRAME_POOL_SIZE)
    for i in 0..<INITIAL_FRAME_POOL_SIZE:
      FRAMES.add(cast[Frame](alloc0(sizeof(FrameObj))))
      FRAME_ALLOCS.inc()  # Count the pre-allocated frames


  if REF_POOL.len == 0:
    REF_POOL = newSeqOfCap[ptr Reference](INITIAL_REF_POOL_SIZE)
    for i in 0..<INITIAL_REF_POOL_SIZE:
      REF_POOL.add(cast[ptr Reference](alloc0(sizeof(Reference))))

  let r = new_ref(VkApplication)
  r.app = new_app()
  r.app.global_ns = new_namespace("global").to_value()
  r.app.gene_ns   = new_namespace("gene"  ).to_value()
  r.app.genex_ns  = new_namespace("genex" ).to_value()
  App = r.to_ref_value()

  # Create built-in GeneException class
  # TODO: Rename to Exception once symbol collision is fixed
  let exception_class = new_class("GeneException")
  let exception_ref = new_ref(VkClass)
  exception_ref.class = exception_class
  # Add to global namespace so it's accessible everywhere
  App.app.global_ns.ref.ns["GeneException".to_key()] = exception_ref.to_ref_value()

  # Add genex to global namespace (similar to gene-new)
  App.app.global_ns.ref.ns["genex".to_key()] = App.app.genex_ns

  # Pre-populate genex with commonly used extensions
  # This creates the namespace entry but doesn't load the extension yet
  App.app.genex_ns.ref.ns["http".to_key()] = NIL

  # Add time namespace stub to prevent errors
  let time_ns = new_namespace("time")
  # Simple time function that returns current timestamp
  proc time_now(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
    return epochTime().to_value()

  var time_now_fn = new_ref(VkNativeFn)
  time_now_fn.native_fn = time_now
  time_ns["now".to_key()] = time_now_fn.to_ref_value()
  App.app.global_ns.ref.ns["time".to_key()] = time_ns.to_value()
  # Also add to gene namespace for gene/time/now access
  App.app.gene_ns.ref.ns["time".to_key()] = time_ns.to_value()

  refresh_env_map()
  set_program_args("", @[])

  # Initialize thread-local namespace for main thread
  # This holds thread-specific variables like $thread and $main_thread
  VM.thread_local_ns = new_namespace("thread_local")

  # For main thread, $thread and $main_thread are the same
  let main_thread_ref = type_defs.Thread(
    id: 0,
    secret: THREADS[0].secret
  )
  VM.thread_local_ns["$thread".to_key()] = main_thread_ref.to_value()
  VM.thread_local_ns["$main_thread".to_key()] = main_thread_ref.to_value()
  VM.thread_local_ns["thread".to_key()] = main_thread_ref.to_value()
  VM.thread_local_ns["main_thread".to_key()] = main_thread_ref.to_value()

  for callback in VmCreatedCallbacks:
    callback()

#################### Helpers #####################

proc refresh_env_map*() =
  if App == NIL or App.kind != VkApplication:
    return
  var env_table = initTable[Key, Value]()
  for pair in envPairs():
    env_table[pair.key.to_key()] = pair.value.to_value()
  App.app.gene_ns.ref.ns["env".to_key()] = new_map_value(env_table)

proc set_program_args*(program: string, args: seq[string]) =
  if App == NIL or App.kind != VkApplication:
    init_app_and_vm()
    if App == NIL or App.kind != VkApplication:
      return
  App.app.args = args
  let arr_ref = new_ref(VkArray)
  arr_ref.arr = @[]
  for arg in args:
    arr_ref.arr.add(arg.to_value())
  App.app.gene_ns.ref.ns["args".to_key()] = arr_ref.to_ref_value()
  App.app.gene_ns.ref.ns["program".to_key()] = program.to_value()

const SYM_UNDERSCORE* = SYMBOL_TAG or 0
const SYM_SELF* = SYMBOL_TAG or 1
const SYM_GENE* = SYMBOL_TAG or 2
const SYM_NS* = SYMBOL_TAG or 3
const SYM_CONTAINER* = SYMBOL_TAG or 4

proc init_values*() =
  SYMBOLS = ManagedSymbols()
  discard "_".to_symbol_value()
  discard "self".to_symbol_value()
  discard "gene".to_symbol_value()
  discard "container".to_symbol_value()

init_values()
