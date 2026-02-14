import os, parseopt

import ../gene/formatter
import ../gene/parser
import ./base

const DEFAULT_COMMAND = "fmt"
const COMMANDS = @[DEFAULT_COMMAND]

type
  FmtOptions = object
    help: bool
    check: bool
    files: seq[string]

proc handle*(cmd: string, args: seq[string]): CommandResult

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("fmt [--check] <file.gene> [...]: format Gene source files")
  manager.add_help("  --check: verify canonical formatting without modifying files")

let short_no_val = {'h'}
let long_no_val = @[
  "help",
  "check",
]

let help_text = """
Usage: gene fmt [options] <file.gene>...

Format Gene source files using canonical style.

Options:
  -h, --help      Show this help message
  --check         Check formatting only (non-zero exit if any file is not canonical)

Examples:
  gene fmt src/main.gene
  gene fmt --check src/main.gene src/lib.gene
"""

proc parse_args(args: seq[string]): (FmtOptions, string) =
  var options: FmtOptions

  if args.len == 0:
    return (options, "")

  for kind, key, _ in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      options.files.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "h", "help":
        options.help = true
      of "check":
        options.check = true
      else:
        return (options, "Unknown option: " & key)
    of cmdEnd:
      discard

  (options, "")

proc format_single_file(path: string, check_only: bool): CommandResult =
  if not fileExists(path):
    return failure("File not found: " & path)

  let source = readFile(path)

  try:
    let formatted = format_source(source, path)
    let normalized = normalize_newlines(source)

    if check_only:
      if formatted != normalized:
        return failure("File is not canonically formatted: " & path)
      return success()

    if formatted != normalized:
      writeFile(path, formatted)

    return success()
  except ParseError as e:
    return failure("Parse error in " & path & ": " & e.msg)
  except CatchableError as e:
    return failure("Formatting failed for " & path & ": " & e.msg)

proc handle*(cmd: string, args: seq[string]): CommandResult =
  let (options, parse_error) = parse_args(args)

  if parse_error.len > 0:
    return failure(parse_error)

  if options.help:
    return success(help_text)

  if options.files.len == 0:
    return failure("No input files provided")

  for path in options.files:
    let step_result = format_single_file(path, options.check)
    if not step_result.success:
      return step_result

  if options.check:
    return success("All files are canonically formatted")

  return success()

when isMainModule:
  let result = handle(DEFAULT_COMMAND, @[])
  if not result.success:
    echo "Failed with error: " & result.error
