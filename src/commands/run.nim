import parseopt, times, strformat, terminal, os, strutils

import ../gene/types
import ../gene/vm
import ../gene/compiler
import ../gene/gir
import ./base

const DEFAULT_COMMAND = "run"
const COMMANDS = @[DEFAULT_COMMAND]

type
  Options = ref object
    benchmark: bool
    debugging: bool
    print_result: bool
    repl_on_error: bool
    trace: bool
    trace_instruction: bool
    compile: bool
    profile: bool
    profile_instructions: bool
    no_gir_cache: bool  # Ignore GIR cache
    file: string
    args: seq[string]

proc handle*(cmd: string, args: seq[string]): CommandResult

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("run <file>: parse and execute <file>")

let short_no_val = {'d'}
let long_no_val = @[
  "repl-on-error",
  "trace",
  "trace-instruction",
  "compile",
  "profile",
  "profile-instructions",
  "no-gir-cache",
]
proc parse_options(args: seq[string]): Options =
  result = Options()
  var found_file = false
  
  # Workaround: get_opt reads from command line when given empty args
  if args.len == 0:
    return
  
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      if not found_file:
        found_file = true
        result.file = key
      result.args.add(key)
    of cmdLongOption, cmdShortOption:
      if found_file:
        result.args.add(key)
        if value != "":
          result.args.add(value)
      else:
        case key
        of "d", "debug":
          result.debugging = true
        of "repl-on-error":
          result.repl_on_error = true
        of "trace":
          result.trace = true
        of "trace-instruction":
          result.trace_instruction = true
        of "compile":
          result.compile = true
        of "profile":
          result.profile = true
        of "profile-instructions":
          result.profile_instructions = true
        of "no-gir-cache":
          result.no_gir_cache = true
        else:
          echo "Unknown option: ", key
          discard
    of cmdEnd:
      discard

proc handle*(cmd: string, args: seq[string]): CommandResult =
  let options = parse_options(args)
  setup_logger(options.debugging)

  # let thread_id = get_free_thread()
  # init_thread(thread_id)
  init_app_and_vm()
  init_stdlib()
  # VM.thread_id = thread_id
  # VM.repl_on_error = options.repl_on_error
  # VM.app.args = options.args

  var file = options.file
  var code: string
  
  # Check if file is provided or read from stdin
  if file == "":
    # No file provided, try to read from stdin
    if not stdin.isatty():
      var lines: seq[string] = @[]
      var line: string
      while stdin.readLine(line):
        lines.add(line)
      if lines.len > 0:
        code = lines.join("\n")
        file = "<stdin>"
      else:
        return failure("No input provided. Provide a file to run.")
    else:
      return failure("No file provided to run.")
  else:
    # Check if file exists
    if not fileExists(file):
      return failure("File not found: " & file)
    
    # Check if it's a .gir file
    if file.endsWith(".gir"):
      # Load and run precompiled GIR directly
      let start = cpu_time()
      
      # Initialize the VM if not already initialized
      init_app_and_vm()
      init_stdlib()
      set_cmd_args(options.args)
      
      # Enable tracing/profiling if requested
      if options.trace:
        VM.trace = true
      if options.profile:
        VM.profiling = true
      if options.profile_instructions:
        VM.instruction_profiling = true
      
      try:
        # Load the GIR file
        let compiled = load_gir(file)
        
        if options.compile or options.debugging:
          echo "=== Loaded GIR: " & file & " ==="
          echo "Instructions: " & $compiled.instructions.len
        
        # Execute the loaded compilation unit
        if VM.frame == nil:
          VM.frame = new_frame(new_namespace(file))
        VM.cu = compiled
        let value = VM.exec()
        
        let elapsed = cpu_time() - start
        
        # Print profiling results if requested
        if options.profile:
          VM.print_profile()
        if options.profile_instructions:
          VM.print_instruction_profile()
        
        if options.benchmark:
          echo fmt"Execution time: {elapsed * 1000:.3f} ms"
        
        return success()
      except CatchableError as e:
        return failure("Loading GIR file: " & e.msg)
    
    # Regular .gene file - check for cached GIR
    if not options.no_gir_cache:
      let gir_path = get_gir_path(file, "build")
      if fileExists(gir_path) and is_gir_up_to_date(gir_path, file):
        # Use cached GIR
        if options.debugging:
          echo "Using cached GIR: " & gir_path
        
        let start = cpu_time()
        init_app_and_vm()
        init_stdlib()
        set_cmd_args(options.args)
        
        if options.trace:
          VM.trace = true
        if options.profile:
          VM.profiling = true
        if options.profile_instructions:
          VM.instruction_profiling = true
        
        try:
          let compiled = load_gir(gir_path)
          
          if VM.frame == nil:
            VM.frame = new_frame(new_namespace(file))
          VM.cu = compiled
          let value = VM.exec()
          
          let elapsed = cpu_time() - start
          
          if options.profile:
            VM.print_profile()
          if options.profile_instructions:
            VM.print_instruction_profile()
          
          if options.benchmark:
            echo fmt"Execution time: {elapsed * 1000:.3f} ms (from cache)"
          
          return success()
        except CatchableError:
          # Fall back to compilation if GIR load fails
          discard
    
    # Read and compile source file
    code = readFile(file)
  
  let start = cpu_time()
  var value: Value
  
  # Initialize the VM if not already initialized
  init_app_and_vm()
  init_stdlib()
  set_cmd_args(options.args)
  
  # Enable tracing if requested
  if options.trace:
    VM.trace = true
  
  # Enable profiling if requested
  if options.profile:
    VM.profiling = true
  
  # Enable instruction profiling if requested
  if options.profile_instructions:
    VM.instruction_profiling = true
  
  if options.trace_instruction:
    # Show both compilation and execution with trace
    echo "=== Compilation Output ==="
    let compiled = parse_and_compile(code, file)
    echo "Instructions:"
    for i, instr in compiled.instructions:
      echo fmt"{i:04X} {instr}"
    echo ""
    echo "=== Execution Trace ==="
    VM.trace = true
    # Initialize frame if needed
    if VM.frame == nil:
      VM.frame = new_frame(new_namespace(file))
    VM.cu = compiled
    value = VM.exec()
  elif options.compile or options.debugging:
    echo "=== Compilation Output ==="
    let compiled = parse_and_compile(code, file)
    echo "Instructions:"
    for i, instr in compiled.instructions:
      echo fmt"{i:03d}: {instr}"
    echo ""
    
    if not options.trace:  # If not tracing, just show compilation
      VM.cu = compiled
      value = VM.exec()
    else:
      echo "=== Execution Trace ==="
      VM.cu = compiled
      value = VM.exec()
  else:
    value = VM.exec(code, file)
  
  if options.print_result:
    echo value
  if options.benchmark:
    echo "Time: " & $(cpu_time() - start)
  if options.profile:
    VM.print_profile()
  if options.profile_instructions:
    VM.print_instruction_profile()
  
  return success()

when isMainModule:
  let cmd = DEFAULT_COMMAND
  let args: seq[string] = @[]
  let result = handle(cmd, args)
  if not result.success:
    echo "Failed with error: " & result.error
