# Gene Intermediate Representation (GIR) serialization/deserialization
import streams, hashes, os, times, json, strutils
import ./types

const 
  GIR_MAGIC = "GENE"
  GIR_VERSION* = 1'u32
  COMPILER_VERSION = "0.1.0"
  
type
  GirHeader* = object
    magic*: array[4, char]
    version*: uint32
    compiler_version*: string
    vm_abi*: string
    timestamp*: int64
    debug*: bool
    published*: bool
    source_hash*: Hash
    
  GirFile* = object
    header*: GirHeader
    constants*: seq[Value]
    symbols*: seq[string]
    instructions*: seq[Instruction]
    metadata*: JsonNode
    kind*: string
    unit_id*: Id
    skip_return*: bool

# Serialization helpers
proc write_string(stream: Stream, s: string) =
  stream.write(s.len.uint32)
  if s.len > 0:
    stream.write(s)

proc read_string(stream: Stream): string =
  let len = stream.readUint32()
  if len > 0:
    result = newString(len)
    discard stream.readData(result[0].addr, len.int)

proc write_value(stream: Stream, v: Value) =
  # Special handling for scope trackers - write NIL instead
  if v.kind == VkScopeTracker:
    stream.write(VkNil.uint16)
    return
  
  # Write value kind
  stream.write(v.kind.uint16)
  
  case v.kind:
  of VkNil, VkVoid, VkPlaceholder:
    # No data
    discard
  of VkBool:
    stream.write(if v == TRUE: 1'u8 else: 0'u8)
  of VkInt:
    stream.write(v.int64)
  of VkFloat:
    stream.write(v.float64)
  of VkString:
    stream.write_string(v.str)
  of VkSymbol:
    stream.write_string(v.str)
  of VkChar:
    stream.write(v.char.uint32)
  else:
    # Complex types stored as indices into constant pool
    # or serialized separately
    stream.write(cast[uint64](v))

proc read_value(stream: Stream): Value =
  let kind = cast[ValueKind](stream.readUint16())
  
  case kind:
  of VkNil:
    result = NIL
  of VkVoid:
    result = VOID
  of VkPlaceholder:
    result = PLACEHOLDER
  of VkBool:
    result = if stream.readUint8() == 1: TRUE else: FALSE
  of VkInt:
    result = stream.readInt64().to_value()
  of VkFloat:
    result = stream.readFloat64().to_value()
  of VkString:
    result = stream.read_string().to_value()
  of VkSymbol:
    result = stream.read_string().to_symbol_value()
  of VkChar:
    result = stream.readUint32().char.to_value()
  else:
    # Complex types - read raw value for now
    result = cast[Value](stream.readUint64())

proc write_instruction(stream: Stream, inst: Instruction) =
  stream.write(inst.kind.uint16)
  stream.write(inst.label.uint32)
  stream.write_value(inst.arg0)
  stream.write(inst.arg1)

proc read_instruction(stream: Stream): Instruction =
  result.kind = cast[InstructionKind](stream.readUint16())
  result.label = stream.readUint32().Label
  result.arg0 = stream.read_value()
  result.arg1 = stream.readInt32()

# Main serialization functions
proc save_gir*(cu: CompilationUnit, path: string, source_path: string = "", debug: bool = false) =
  ## Save a compilation unit to a GIR file
  let dir = path.parentDir()
  if dir != "" and not dirExists(dir):
    createDir(dir)
  
  var stream = newFileStream(path, fmWrite)
  if stream == nil:
    raise new_exception(types.Exception, "Failed to open file for writing: " & path)
  defer: stream.close()
  
  # Write header
  var header: GirHeader
  header.magic = ['G', 'E', 'N', 'E']
  header.version = GIR_VERSION
  header.compiler_version = COMPILER_VERSION
  header.vm_abi = "nim-" & NimVersion & "-" & $sizeof(pointer) & "bit"
  header.timestamp = 0'i64  # TODO: Fix epochTime conversion
  header.debug = debug
  header.published = false
  
  # Calculate source hash if provided
  if source_path != "" and fileExists(source_path):
    let source_content = readFile(source_path)
    let raw_hash = cast[uint64](hash(source_content))
    let truncated = raw_hash and 0x7FFF_FFFF_FFFF_FFFF'u64
    header.source_hash = cast[Hash](truncated.int)
    let info = getFileInfo(source_path)
    header.timestamp = info.lastWriteTime.toUnix()
  else:
    header.timestamp = now().toTime().toUnix()
  
  # Write header fields
  stream.write(header.magic)
  stream.write(header.version)
  stream.write_string(header.compiler_version)
  stream.write_string(header.vm_abi)
  stream.write(header.timestamp)
  stream.write(header.debug)
  stream.write(header.published)
  let stored_hash = cast[int64](header.source_hash)
  stream.write(stored_hash)
  
  # Collect constants from instructions
  var constants: seq[Value] = @[]
  # Skip constant collection for now - causing issues
  # TODO: Fix constant pooling
  
  # Write constants
  stream.write(constants.len.uint32)
  for c in constants:
    stream.write_value(c)
  
  # Write symbol table (for now empty - will be populated from global symbols)
  stream.write(0'u32)  # symbol count
  
  # Write instructions
  stream.write(cu.instructions.len.uint32)
  for inst in cu.instructions:
    stream.writeInstruction(inst)
  
  # Write metadata as simple values for now
  stream.write_string($cu.kind)
  stream.write(cast[int64](cu.id))
  stream.write(cu.skip_return)

proc load_gir_file*(path: string): GirFile =
  ## Load a GIR file and return its structured contents
  if not fileExists(path):
    raise new_exception(types.Exception, "GIR file not found: " & path)

  var stream = newFileStream(path, fmRead)
  if stream == nil:
    raise new_exception(types.Exception, "Failed to open GIR file: " & path)
  defer: stream.close()

  var header: GirHeader
  discard stream.readData(header.magic[0].addr, 4)
  if header.magic != ['G', 'E', 'N', 'E']:
    raise new_exception(types.Exception, "Invalid GIR file: bad magic")

  header.version = stream.readUint32()
  if header.version != GIR_VERSION:
    raise new_exception(types.Exception, "Unsupported GIR version: " & $header.version)

  header.compiler_version = stream.read_string()
  header.vm_abi = stream.read_string()
  header.timestamp = stream.readInt64()
  header.debug = stream.readBool()
  header.published = stream.readBool()
  header.source_hash = stream.readInt64().Hash

  let constant_count = stream.readUint32()
  var constants: seq[Value] = @[]
  for _ in 0..<constant_count:
    constants.add(stream.read_value())

  let symbol_count = stream.readUint32()
  var symbols: seq[string] = @[]
  for _ in 0..<symbol_count:
    symbols.add(stream.read_string())

  let instruction_count = stream.readUint32()
  var instructions: seq[Instruction] = @[]
  for _ in 0..<instruction_count:
    instructions.add(stream.readInstruction())

  let kind_str = stream.read_string()
  let unit_id = stream.readInt64()
  let skip_return = stream.readBool()

  result.header = header
  result.constants = constants
  result.symbols = symbols
  result.instructions = instructions
  result.metadata = newJObject()
  result.metadata["kind"] = newJString(kind_str)
  result.metadata["id"] = newJInt(unit_id)
  result.metadata["skipReturn"] = newJBool(skip_return)
  result.metadata["timestamp"] = newJInt(header.timestamp)
  result.kind = kind_str
  result.unit_id = unit_id.Id
  result.skip_return = skip_return

proc load_gir*(path: string): CompilationUnit =
  ## Load a compilation unit from a GIR file
  let gir_file = load_gir_file(path)
  result = new_compilation_unit()
  result.instructions = gir_file.instructions

  if gir_file.kind.len > 0:
    result.kind = parseEnum[CompilationUnitKind](gir_file.kind)
  result.id = gir_file.unit_id
  result.skip_return = gir_file.skip_return

proc is_gir_up_to_date*(gir_path: string, source_path: string): bool =
  ## Check if a GIR file is up-to-date with its source
  if not fileExists(gir_path):
    return false
  
  if not fileExists(source_path):
    return true  # No source to compare against
  
  # Check modification times
  let gir_info = getFileInfo(gir_path)
  let source_info = getFileInfo(source_path)
  
  if source_info.lastWriteTime > gir_info.lastWriteTime:
    return false
  
  # TODO: Check source hash from GIR header
  return true

proc get_gir_path*(source_path: string, out_dir: string = "build"): string =
  ## Get the output path for a GIR file based on source path
  let (dir, name, _) = splitFile(source_path)
  let rel_dir = if dir.startsWith("/"): dir[1..^1] else: dir
  result = out_dir / rel_dir / name & ".gir"
