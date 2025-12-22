import parseopt
import ../gene/types
import ../gene/vm
import ../gene/repl_session
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

  let ns = new_namespace(App.app.global_ns.ref.ns, "repl")
  let scope_tracker = new_scope_tracker()
  let scope = new_scope(scope_tracker)
  discard run_repl_session(VM, scope_tracker, scope, ns, "<repl>", "gene> ", true)

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
