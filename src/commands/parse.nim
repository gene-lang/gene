import parseopt, strutils, os, tables, terminal
import ../gene/types
import ../gene/parser
import ./base

const DEFAULT_COMMAND = "parse"

type
  ParseOptions = object
    help: bool
    files: seq[string]
    code: string
    format: string  # "pretty" (default), "compact", "sexp"

proc handle*(cmd: string, args: seq[string]): CommandResult

let short_no_val = {'h'}
let long_no_val = @[
  "help",
]

let help_text = """
Usage: gene parse [options] [<file>...]

Parse Gene code and output the parsed AST.

Options:
  -h, --help              Show this help message
  -e, --eval <code>       Parse the given code string
  -f, --format <format>   Output format: pretty (default), compact, sexp

Examples:
  gene parse file.gene               # Parse and display a file
  gene parse -e "(+ 1 2)"            # Parse a code string
  gene parse --format sexp file.gene # Output in S-expression format
"""

proc parse_args(args: seq[string]): ParseOptions =
  result.format = "pretty"
  
  # Workaround: get_opt reads from command line when given empty args
  if args.len == 0:
    return
  
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      result.files.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "h", "help":
        result.help = true
      of "e", "eval":
        result.code = value
      of "f", "format":
        if value in ["pretty", "compact", "sexp"]:
          result.format = value
        else:
          stderr.writeLine("Error: Invalid format '" & value & "'. Must be: pretty, compact, or sexp")
          quit(1)
      else:
        stderr.writeLine("Error: Unknown option: " & key)
        quit(1)
    of cmdEnd:
      discard

proc format_value(value: Value, format: string, indent: int = 0): string =
  case format
  of "compact":
    # Output valid Gene syntax without extra whitespace
    case value.kind
    of VkNil:
      return "nil"
    of VkBool:
      return if value == TRUE: "true" else: "false"
    of VkInt:
      return $value.to_int()
    of VkFloat:
      return $value.to_float()
    of VkChar:
      return "'" & $value.char & "'"
    of VkString:
      # Properly escape strings
      result = "\""
      for ch in value.str:
        case ch
        of '"': result &= "\\\""
        of '\\': result &= "\\\\"
        of '\n': result &= "\\n"
        of '\r': result &= "\\r"
        of '\t': result &= "\\t"
        else: result &= ch
      result &= "\""
    of VkSymbol:
      return value.str
    of VkComplexSymbol:
      return value.ref.csymbol.join("/")
    of VkArray:
      result = "["
      for i, item in array_data(value):
        if i > 0: result &= " "
        result &= format_value(item, format)
      result &= "]"
    of VkMap:
      result = "{"
      var first = true
      for k, v in map_data(value):
        if not first: result &= " "
        let symbol_value = cast[Value](k)
        let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
        result &= "^" & get_symbol(symbol_index.int) & " " & format_value(v, format)
        first = false
      result &= "}"
    of VkGene:
      result = "("
      result &= format_value(value.gene.type, format)
      # Add properties
      for k, v in value.gene.props:
        let symbol_value = cast[Value](k)
        let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
        result &= " ^" & get_symbol(symbol_index.int) & " " & format_value(v, format)
      # Add children
      for child in value.gene.children:
        result &= " " & format_value(child, format)
      result &= ")"
    else:
      return $value
  of "sexp":
    # S-expression format (similar to compact but with : for props)
    case value.kind
    of VkGene:
      result = "("
      result &= format_value(value.gene.type, "compact")
      for k, v in value.gene.props:
        let symbol_value = cast[Value](k)
        let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
        result &= " :" & get_symbol(symbol_index.int) & " " & format_value(v, "compact")
      for child in value.gene.children:
        result &= " " & format_value(child, "compact")
      result &= ")"
    else:
      return format_value(value, "compact")
  else:  # "pretty"
    let spaces = "  ".repeat(indent)
    case value.kind
    of VkNil:
      return spaces & "nil"
    of VkBool:
      return spaces & (if value == TRUE: "true" else: "false")
    of VkInt:
      return spaces & $value.to_int()
    of VkFloat:
      return spaces & $value.to_float()
    of VkChar:
      return spaces & "'" & $value.char & "'"
    of VkString:
      # Properly escape strings
      result = spaces & "\""
      for ch in value.str:
        case ch
        of '"': result &= "\\\""
        of '\\': result &= "\\\\"
        of '\n': result &= "\\n"
        of '\r': result &= "\\r"
        of '\t': result &= "\\t"
        else: result &= ch
      result &= "\""
    of VkSymbol:
      return spaces & value.str
    of VkComplexSymbol:
      return spaces & value.ref.csymbol.join("/")
    of VkArray:
      if array_data(value).len == 0:
        return spaces & "[]"
      result = spaces & "[\n"
      for item in array_data(value):
        result &= format_value(item, format, indent + 1) & "\n"
      result &= spaces & "]"
    of VkMap:
      if map_data(value).len == 0:
        return spaces & "{}"
      result = spaces & "{\n"
      for k, v in map_data(value):
        let symbol_value = cast[Value](k)
        let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
        result &= spaces & "  ^" & get_symbol(symbol_index.int) & " " & format_value(v, "compact") & "\n"
      result &= spaces & "}"
    of VkGene:
      result = spaces & "(" & format_value(value.gene.type, "compact")
      # Add properties inline
      for k, v in value.gene.props:
        let symbol_value = cast[Value](k)
        let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
        result &= " ^" & get_symbol(symbol_index.int) & " " & format_value(v, "compact")
      # Add children
      if value.gene.children.len > 0:
        result &= "\n"
        for child in value.gene.children:
          result &= format_value(child, format, indent + 1) & "\n"
        result &= spaces
      result &= ")"
    else:
      return spaces & $value

proc handle*(cmd: string, args: seq[string]): CommandResult =
  let options = parse_args(args)
  
  if options.help:
    echo help_text
    return success()
  
  var code: string
  var source_name: string
  
  if options.code != "":
    code = options.code
    source_name = "<eval>"
  elif options.files.len > 0:
    # Parse files
    for file in options.files:
      if not fileExists(file):
        stderr.writeLine("Error: File not found: " & file)
        quit(1)
      
      code = readFile(file)
      source_name = file
      
      # Only show header for pretty format or when multiple files
      if options.format == "pretty" or options.files.len > 1:
        echo "=== Parsing: " & source_name & " ==="
      
      try:
        let parsed = read_all(code)
        
        if parsed.len == 0:
          echo "(empty)"
        else:
          for i, value in parsed:
            if i > 0:
              echo ""
            echo format_value(value, options.format)
      except ParseError as e:
        stderr.writeLine("Parse error in " & source_name & ": " & e.msg)
        quit(1)
    
    return success()
  else:
    # No code or files provided, try to read from stdin
    if not stdin.isatty():
      var lines: seq[string] = @[]
      var line: string
      while stdin.readLine(line):
        lines.add(line)
      if lines.len > 0:
        code = lines.join("\n")
        source_name = "<stdin>"
      else:
        stderr.writeLine("Error: No input provided. Use -e for code or provide a file.")
        quit(1)
    else:
      stderr.writeLine("Error: No input provided. Use -e for code or provide a file.")
      quit(1)
  
  # Parse single code string
  try:
    let parsed = read_all(code)
    
    if parsed.len == 0:
      echo "(empty)"
    else:
      for i, value in parsed:
        if i > 0:
          echo ""
        echo format_value(value, options.format)
  except ParseError as e:
    stderr.writeLine("Parse error: " & e.msg)
    quit(1)
  
  return success()

proc init*(manager: CommandManager) =
  manager.register("parse", handle)
  manager.add_help("  parse    Parse Gene code and output AST")
