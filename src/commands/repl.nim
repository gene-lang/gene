import parseopt, strutils
import ../gene/types
import ../gene/vm
import ./base

const DEFAULT_COMMAND = "repl"
const COMMANDS = @[DEFAULT_COMMAND, "r"]

type
  Options = ref object
    debugging: bool

proc handle*(cmd: string, args: seq[string]): CommandResult

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("repl: start an interactive REPL")
  manager.add_help("  -d, --debug: enable debug output")

let short_no_val = {'d'}
let long_no_val: seq[string] = @[]

proc parse_options(args: seq[string]): Options =
  result = Options()
  
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      discard  # REPL doesn't take arguments
    of cmdLongOption, cmdShortOption:
      case key
      of "d", "debug":
        result.debugging = true
      else:
        echo "Unknown option: ", key
    of cmdEnd:
      discard

proc start_repl(debugging: bool) =
  setup_logger(debugging)
  init_app_and_vm()
  init_stdlib()
  
  echo "Gene REPL - Interactive Gene Language Shell"
  echo "Type 'exit' or 'quit' to exit, 'help' for help"
  echo ""
  
  var line_number = 1
  
  while true:
    stdout.write("gene> ")
    stdout.flushFile()
    
    var input: string
    if read_line(stdin, input):
      let trimmed = input.strip()
      
      if trimmed.len == 0:
        continue
        
      if trimmed == "exit" or trimmed == "quit":
        break
        
      if trimmed == "help":
        echo "Gene REPL Help:"
        echo "  exit, quit: Exit the REPL"
        echo "  help: Show this help message"
        echo "  Any other input is evaluated as Gene code"
        continue
      
      try:
        let value = VM.exec(trimmed, "<repl>")
        # Only print return value if it's not nil/void and not from print/println statements
        if not value.is_nil() and value.kind != VkVoid and not trimmed.starts_with("(print") and not trimmed.starts_with("(println"):
          echo $value
      except ValueError as e:
        echo "Error: ", e.msg
        
      inc(line_number)
    else:
      # EOF (Ctrl+D)
      break

proc handle*(cmd: string, args: seq[string]): CommandResult =
  let options = parse_options(args)
  start_repl(options.debugging)
  return success()

when isMainModule:
  let cmd = DEFAULT_COMMAND
  let args: seq[string] = @[]
  let result = handle(cmd, args)
  if not result.success:
    echo "Failed with error: " & result.error