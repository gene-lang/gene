import parseopt, os
import ../gene/types
import ../gene/vm
import ../gene/repl_session
import ./base
import ./package_context

const DEFAULT_COMMAND = "repl"
const COMMANDS = @[DEFAULT_COMMAND, "r"]

type
  Options = ref object
    debugging: bool
    pkg: string

proc handle*(cmd: string, args: seq[string]): CommandResult

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("repl: start an interactive REPL")
  manager.add_help("  --pkg <package>: start the REPL in a package context")
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
      of "pkg":
        result.pkg = value
      else:
        echo "Unknown option: ", key
    of cmdEnd:
      discard

proc start_repl(debugging: bool, pkg_ctx: CliPackageContext) =
  setup_logger(debugging)
  init_app_and_vm()
  init_stdlib()
  set_program_args("<repl>", @[])

  let module_name = virtual_module_name(pkg_ctx, "repl", "<repl>")
  let ns = new_namespace(App.app.global_ns.ref.ns, module_name)
  configure_main_namespace(ns, module_name, pkg_ctx)
  let scope_tracker = new_scope_tracker()
  let scope = new_scope(scope_tracker)
  discard run_repl_session(VM, scope_tracker, scope, ns, module_name, "gene> ", true)

proc handle*(cmd: string, args: seq[string]): CommandResult =
  let options = parse_options(args)
  var pkg_ctx = disabled_cli_package_context()
  try:
    pkg_ctx = resolve_cli_package_context(options.pkg, getCurrentDir(), "<repl>")
  except CatchableError as e:
    return failure(e.msg)
  start_repl(options.debugging, pkg_ctx)
  return success()

when isMainModule:
  let cmd = DEFAULT_COMMAND
  let args: seq[string] = @[]
  let result = handle(cmd, args)
  if not result.success:
    echo "Failed with error: " & result.error
