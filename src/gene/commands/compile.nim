import parseopt, strutils, os, terminal
import ../types
import ../parser
import ../compiler
import ../gir
import ./base

const DEFAULT_COMMAND = "compile"

type
  CompileOptions = object
    help: bool
    files: seq[string]
    code: string
    format: string  # "pretty" (default), "compact", "bytecode", "gir"
    show_addresses: bool
    out_dir: string  # Output directory for GIR files
    force: bool      # Force rebuild even if cache is up-to-date
    emit_debug: bool # Include debug info in GIR

proc handle*(cmd: string, args: seq[string]): CommandResult

let short_no_val = {'h', 'a'}
let long_no_val = @[
  "help",
  "addresses",
  "force",
  "emit-debug",
]

let help_text = """
Usage: gene compile [options] [<file>...]

Compile Gene code to bytecode or Gene IR (.gir) format.

Options:
  -h, --help              Show this help message
  -e, --eval <code>       Compile the given code string
  -f, --format <format>   Output format: pretty (default), compact, bytecode, gir
  -o, --out-dir <dir>     Output directory for GIR files (default: build/)
  -a, --addresses         Show instruction addresses
  --force                 Rebuild even if cache is up-to-date
  --emit-debug            Include debug info in GIR files

Examples:
  gene compile file.gene                  # Compile to build/file.gir
  gene compile -f pretty file.gene        # Display instructions
  gene compile -e "(+ 1 2)"               # Compile a code string
  gene compile -o out src/app.gene        # Output to out/src/app.gir
  gene compile --force file.gene          # Force recompilation
"""

proc parseArgs(args: seq[string]): CompileOptions =
  result.format = ""  # Will be set based on context
  result.out_dir = "build"
  
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
      of "a", "addresses":
        result.show_addresses = true
      of "e", "eval":
        result.code = value
      of "f", "format":
        if value == "":
          stderr.writeLine("Error: Format option requires a value")
          quit(1)
        elif value in ["pretty", "compact", "bytecode", "gir"]:
          result.format = value
        else:
          stderr.writeLine("Error: Invalid format '" & value & "'. Must be: pretty, compact, bytecode, or gir")
          quit(1)
      of "o", "out-dir":
        result.out_dir = value
      of "force":
        result.force = true
      of "emit-debug":
        result.emit_debug = true
      else:
        stderr.writeLine("Error: Unknown option: " & key)
        quit(1)
    of cmdEnd:
      discard
  
  # Default format based on context - moved after processing all arguments
  discard

proc formatValue(value: Value): string =
  case value.kind
  of VkNil: result = "nil"
  of VkBool: result = if value == TRUE: "true" else: "false"
  of VkInt: result = $value.to_int()
  of VkFloat: result = $value.to_float()
  of VkChar: result = "'" & $value.char & "'"
  of VkString: result = "\"" & value.str & "\""
  of VkSymbol: result = value.str
  else: result = $value

proc formatInstruction(inst: Instruction, index: int, format: string, show_addresses: bool): string =
  case format
  of "bytecode":
    # Raw bytecode format
    result = $inst.kind
    case inst.kind
    # Instructions with no arguments
    of IkNoop, IkEnd, IkScopeEnd, IkSelf, IkSetSelf, IkRotate, IkParse, IkRender,
       IkEval, IkPushNil, IkPushSelf, IkPop, IkDup, IkDup2, IkDupSecond, IkSwap,
       IkOver, IkLen, IkArrayStart, IkArrayEnd, IkMapStart,
       IkMapEnd, IkGeneStart, IkGeneEnd, IkGeneSetType, IkGeneAddChild,
       IkGetChildDynamic, IkGetMemberOrNil, IkGetMemberDefault, IkAdd, IkSub,
       IkMul, IkDiv, IkLt, IkLe, IkGt, IkGe, IkEq, IkNe, IkAnd, IkOr, IkNot,
       IkNeg, IkCreateRange, IkCreateEnum, IkEnumAddMember, IkReturn,
       IkThrow, IkCatchEnd, IkCatchRestore, IkFinally, IkFinallyEnd,
       IkLoopStart, IkLoopEnd, IkNew, IkGetClass, IkIsInstance, IkSuper,
       IkCallerEval, IkAsync, IkAwait, IkAsyncStart, IkAsyncEnd, IkCompileInit,
       IkCallInit, IkStart, IkImport, IkPow:
      # No arguments
      discard
    # Instructions with arg0
    of IkPushValue, IkScopeStart, IkVar, IkVarResolve, IkVarAssign,
       IkResolveSymbol, IkJump, IkJumpIfFalse, IkContinue, IkBreak,
       IkGeneStartDefault, IkSubValue, IkAddValue, IkLtValue, IkFunction,
       IkMacro, IkBlock, IkCompileFn, IkNamespace, IkNamespaceStore,
       IkClass, IkSubClass, IkDefineMethod, IkResolveMethod,
       IkAssign, IkData:
      result &= " " & $inst.arg0
    of IkSetMember, IkGetMember:
      let key = inst.arg0.Key
      let symbol_value = cast[Value](key)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= " " & get_symbol(symbol_index.int)
    of IkMapSetProp, IkGeneSetProp:
      let key = inst.arg0.Key
      let symbol_value = cast[Value](key)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= " " & get_symbol(symbol_index.int)
    of IkSetChild, IkGetChild:
      result &= " " & $inst.arg0.int64
    # Instructions with both args
    of IkVarValue, IkVarResolveInherited, IkVarAssignInherited,
       IkJumpIfMatchSuccess, IkTryStart, IkTryEnd, IkCatchStart:
      result &= " " & $inst.arg0
      if inst.arg1 != 0:
        result &= " " & $inst.arg1
    else:
      # Fallback for any unhandled instructions
      if inst.arg0.kind != VkNil:
        result &= " " & $inst.arg0
      if inst.arg1.kind != VkNil:
        result &= " " & $inst.arg1
  of "compact":
    result = $inst
  else:  # "pretty"
    if show_addresses:
      result = index.toHex(4) & "  "
    else:
      result = "  "
    
    result &= ($inst.kind).alignLeft(20)
    
    # Add arguments based on instruction type - only show args that are actually used
    case inst.kind
    # Instructions with no arguments
    of IkNoop, IkEnd, IkScopeEnd, IkSelf, IkSetSelf, IkRotate, IkParse, IkRender,
       IkEval, IkPushNil, IkPushSelf, IkPop, IkDup, IkDup2, IkDupSecond, IkSwap,
       IkOver, IkLen, IkArrayStart, IkArrayEnd, IkMapStart,
       IkMapEnd, IkGeneStart, IkGeneEnd, IkGeneSetType, IkGeneAddChild,
       IkGetChildDynamic, IkGetMemberOrNil, IkGetMemberDefault, IkAdd, IkSub,
       IkMul, IkDiv, IkLt, IkLe, IkGt, IkGe, IkEq, IkNe, IkAnd, IkOr, IkNot,
       IkNeg, IkCreateRange, IkCreateEnum, IkEnumAddMember, IkReturn,
       IkThrow, IkCatchEnd, IkCatchRestore, IkFinally, IkFinallyEnd,
       IkLoopStart, IkLoopEnd, IkNew, IkGetClass, IkIsInstance, IkSuper,
       IkCallerEval, IkAsync, IkAwait, IkAsyncStart, IkAsyncEnd, IkCompileInit,
       IkCallInit:
      # No arguments to display
      discard
    
    # Instructions with only arg0
    of IkData:
      result &= formatValue(inst.arg0)
    of IkPushValue:
      result &= formatValue(inst.arg0)
    of IkScopeStart:
      if inst.arg0.kind == VkScopeTracker:
        result &= "<scope>"
      elif inst.arg0.kind != VkNil:
        result &= formatValue(inst.arg0)
    of IkVar, IkVarResolve, IkVarAssign:
      if inst.arg0.kind == VkInt:
        result &= "var[" & $inst.arg0.int64 & "]"
      else:
        result &= formatValue(inst.arg0)
    of IkResolveSymbol:
      if inst.arg0.kind == VkSymbol:
        result &= inst.arg0.str
      else:
        result &= formatValue(inst.arg0)
    of IkSetMember, IkGetMember:
      let key = inst.arg0.Key
      let symbol_value = cast[Value](key)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= "." & get_symbol(symbol_index.int)
    of IkSetChild, IkGetChild:
      result &= "[" & $inst.arg0.int64 & "]"
    of IkJump, IkJumpIfFalse:
      result &= "-> " & inst.arg0.int64.toHex(4)
    of IkContinue, IkBreak:
      if inst.arg0.int64 == -1:
        result &= "<error>"
      else:
        result &= "label=" & $inst.arg0.int64
    of IkMapSetProp, IkGeneSetProp:
      let key = inst.arg0.Key
      let symbol_value = cast[Value](key)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= "^" & get_symbol(symbol_index.int)
    of IkGeneStartDefault:
      if inst.arg0.kind == VkInt:
        result &= "size=" & $inst.arg0.int64
    of IkSubValue, IkAddValue:
      result &= formatValue(inst.arg0)
    of IkLtValue:
      result &= "< " & formatValue(inst.arg0)
    of IkFunction, IkMacro, IkBlock, IkCompileFn:
      if inst.arg0.kind != VkNil:
        result &= formatValue(inst.arg0)
    of IkNamespace:
      if inst.arg0.kind == VkString:
        result &= inst.arg0.str
      elif inst.arg0.kind == VkSymbol:
        result &= inst.arg0.str
      else:
        result &= formatValue(inst.arg0)
    of IkNamespaceStore:
      if inst.arg0.kind == VkSymbol:
        result &= inst.arg0.str
      else:
        result &= formatValue(inst.arg0)
    of IkClass, IkSubClass:
      if inst.arg0.kind == VkString:
        result &= inst.arg0.str
      else:
        result &= formatValue(inst.arg0)
    of IkDefineMethod, IkResolveMethod:
      if inst.arg0.kind == VkSymbol:
        result &= inst.arg0.str
      else:
        result &= formatValue(inst.arg0)

    of IkImport:
      # Import uses stack for the import gene
      discard
    of IkStart:
      # Start has no visible arguments
      discard
    of IkPow:
      # Power operation
      discard
    
    # Instructions with both arg0 and arg1  
    of IkVarValue:
      result &= formatValue(inst.arg0) & " -> var[" & $inst.arg1 & "]"
    of IkVarResolveInherited, IkVarAssignInherited:
      result &= "var[" & $inst.arg0.int64 & "] up=" & $inst.arg1
    of IkJumpIfMatchSuccess:
      result &= "index=" & $inst.arg0.int64 & " -> " & inst.arg1.toHex(4)
    of IkTryStart:
      result &= "catch=" & inst.arg0.int64.toHex(4)
      if inst.arg1 != 0:
        result &= " finally=" & inst.arg1.toHex(4)
    of IkTryEnd:
      # TryEnd uses arg0 and arg1 but they're internal values
      discard
    of IkCatchStart:
      # CatchStart might have exception type in arg0
      if inst.arg0.kind != VkNil:
        result &= "type=" & formatValue(inst.arg0)

    of IkAssign:
      # Assign has symbol in arg0
      if inst.arg0.kind == VkSymbol:
        result &= inst.arg0.str & " ="
      else:
        result &= formatValue(inst.arg0)
    else:
      # For any unhandled instructions, show non-nil arguments
      var shown = false
      if inst.arg0.kind != VkNil:
        result &= formatValue(inst.arg0)
        shown = true
      if inst.arg1.kind != VkNil:
        if shown: result &= " "
        result &= formatValue(inst.arg1)

proc handle*(cmd: string, args: seq[string]): CommandResult =
  var options = parseArgs(args)
  
  # Set default format if not specified
  if options.format == "":
    if options.files.len > 0:
      options.format = "gir"  # Default to GIR for files
    else:
      options.format = "pretty"  # Default to pretty for eval/stdin
  
  if options.help:
    echo help_text
    return success()
  
  var code: string
  var source_name: string
  
  if options.code != "":
    code = options.code
    source_name = "<eval>"
  elif options.files.len > 0:
    # Compile files
    for file in options.files:
      if not fileExists(file):
        stderr.writeLine("Error: File not found: " & file)
        quit(1)
      
      code = readFile(file)
      source_name = file
      
      # Check if GIR output is requested
      if options.format == "gir":
        let gir_path = get_gir_path(file, options.out_dir)
        
        # Check if recompilation is needed
        if not options.force and is_gir_up_to_date(gir_path, file):
          echo "Up-to-date: " & gir_path
          continue
        
        echo "Compiling: " & source_name & " -> " & gir_path
        
        try:
          let parsed = read_all(code)
          let compiled = compile(parsed)
          
          # Save to GIR file
          save_gir(compiled, gir_path, file, options.emit_debug)
          echo "Written: " & gir_path
        except ParseError as e:
          stderr.writeLine("Parse error in " & source_name & ": " & e.msg)
          quit(1)
        except ValueError as e:
          stderr.writeLine("Value error in " & source_name & ": " & e.msg)
          stderr.writeLine("Stack trace: " & e.getStackTrace())
          quit(1)
        except CatchableError as e:
          stderr.writeLine("Compilation error in " & source_name & ": " & e.msg)
          quit(1)
      else:
        # Display instructions
        echo "=== Compiling: " & source_name & " ==="
        
        try:
          let parsed = read_all(code)
          let compiled = compile(parsed)
          
          echo "Instructions (" & $compiled.instructions.len & "):"
          for i, inst in compiled.instructions:
            echo formatInstruction(inst, i, options.format, options.show_addresses)
          
          # TODO: Add matcher display when $ operator is available
          
          echo ""
        except ParseError as e:
          stderr.writeLine("Parse error in " & source_name & ": " & e.msg)
          quit(1)
        except CatchableError as e:
          stderr.writeLine("Compilation error in " & source_name & ": " & e.msg)
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
  
  # Compile single code string
  try:
    let parsed = read_all(code)
    let compiled = compile(parsed)
    
    echo "Instructions (" & $compiled.instructions.len & "):"
    for i, inst in compiled.instructions:
      echo formatInstruction(inst, i, options.format, options.show_addresses)
    
    # TODO: Add matcher display when $ operator is available
  except ParseError as e:
    stderr.writeLine("Parse error: " & e.msg)
    quit(1)
  except CatchableError as e:
    stderr.writeLine("Compilation error: " & e.msg)
    quit(1)
  
  return success()

proc init*(manager: CommandManager) =
  manager.register("compile", handle)
  manager.add_help("  compile  Compile Gene code and output bytecode")