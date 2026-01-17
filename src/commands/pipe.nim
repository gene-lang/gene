import parseopt, strutils
import ../gene/types
import ../gene/vm
import ../gene/compiler
import ./base

const DEFAULT_COMMAND = "pipe"
const COMMANDS = @[DEFAULT_COMMAND]

type
  PipeOptions = ref object
    debugging: bool
    trace: bool
    trace_instruction: bool
    compile: bool
    help: bool
    code: string

proc handle*(cmd: string, args: seq[string]): CommandResult

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("pipe <code>: process stdin line-by-line with <code>")
  manager.add_help("  Each line is available as $line")
  manager.add_help("  -d, --debug: enable debug output")
  manager.add_help("  --trace: enable execution tracing")
  manager.add_help("  --compile: show compilation details")

let short_no_val = {'d', 'h'}
let long_no_val = @[
  "trace",
  "trace-instruction",
  "compile",
  "help",
]

proc parse_options(args: seq[string]): PipeOptions =
  result = PipeOptions()
  var code_parts: seq[string] = @[]

  if args.len == 0:
    return

  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      code_parts.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "d", "debug":
        result.debugging = true
      of "trace":
        result.trace = true
      of "trace-instruction":
        result.trace_instruction = true
      of "compile":
        result.compile = true
      of "h", "help":
        result.help = true
      else:
        echo "Unknown option: ", key
    of cmdEnd:
      discard

  result.code = code_parts.join(" ")

proc set_line_variable(line: string) =
  ## Set the $line variable in global and gene namespaces
  if App == NIL or App.kind != VkApplication:
    init_app_and_vm()
    if App == NIL or App.kind != VkApplication:
      return

  let line_value = line.to_value()
  App.app.gene_ns.ref.ns["line".to_key()] = line_value
  App.app.global_ns.ref.ns["line".to_key()] = line_value

proc handle*(cmd: string, args: seq[string]): CommandResult =
  let options = parse_options(args)

  if options.help:
    return success("""Gene Pipe Command - Line-by-line stream processing

Usage: gene pipe [options] '<code>'

Process stdin line-by-line, executing Gene code for each line.
The current line is available as $line.

Options:
  -h, --help              Show this help message
  -d, --debug             Enable debug output
  --trace                 Enable execution tracing
  --compile               Show compilation details

Examples:
  # Output lines as-is
  cat file.txt | gene pipe '$line'

  # Filter lines (nil results are skipped)
  cat log.txt | gene pipe '(if ($line == "keep") $line)'

  # String interpolation
  ls | gene pipe '#"File: #{$line}"'

  # Process numbers
  seq 1 5 | gene pipe '(* $line/.to_i 2)'

  # Get line length
  cat file.txt | gene pipe '($line .size)'

Notes:
  - Nil results are skipped (enables filtering)
  - Exits with non-zero status on first error
  - Lines are processed in streaming fashion (no buffering)
""")

  setup_logger(options.debugging)

  var code = options.code

  if code.len == 0:
    return failure("No code provided. Usage: gene pipe '<code>'")

  # Initialize VM
  init_app_and_vm()
  init_stdlib()
  set_program_args("<pipe>", @[])

  # Compile code once before processing lines
  var compiled: CompilationUnit
  try:
    compiled = parse_and_compile(code)

    if options.compile or options.debugging:
      echo "=== Compiled Code ==="
      for i, instr in compiled.instructions:
        echo i, ": ", instr
      echo ""
  except CatchableError as e:
    return failure("Compilation error: " & e.msg)

  # Enable tracing if requested
  if options.trace or options.trace_instruction:
    VM.trace = true

  # Process stdin line by line
  var line: string
  var line_num = 0

  while stdin.readLine(line):
    line_num += 1

    # Set $line variable
    set_line_variable(line)

    # Execute the compiled code
    try:
      # Initialize frame if needed
      if VM.frame == nil:
        let ns = new_namespace(App.app.global_ns.ref.ns, "<pipe>")
        ns["__module_name__".to_key()] = "<pipe>".to_value()
        ns["__is_main__".to_key()] = TRUE
        ns["gene".to_key()] = App.app.gene_ns
        ns["genex".to_key()] = App.app.genex_ns
        VM.frame = new_frame(ns)

      VM.cu = compiled
      let result = VM.exec()

      # Print result if not nil (enables filtering)
      if result.kind != VkNil:
        # Output strings without quotes, other types with their default representation
        if result.kind == VkString:
          echo result.str
        else:
          echo $result

    except CatchableError as e:
      stderr.writeLine("Error at line ", line_num, ": ", e.msg)
      return failure("")

  return success()

when isMainModule:
  let cmd = DEFAULT_COMMAND
  let args: seq[string] = @[]
  let result = handle(cmd, args)
  if not result.success:
    echo "Failed with error: " & result.error
