import tables, strutils, sets, os, algorithm, hashes
import std/json
import std/uri

import ./types
import ./parser

type
  Serialization* = ref object
    references*: Table[string, Value]
    data*: Value

  TreeWriteOptions = object
    directory_nodes: HashSet[string]

proc serialize*(self: Serialization, value: Value): Value {.gcsafe.}
proc to_path*(self: Value): string {.gcsafe.}
proc to_path*(self: Class): string {.gcsafe.}
proc is_literal_value*(v: Value): bool {.inline, gcsafe.}
proc serialize_literal*(value: Value): Serialization {.gcsafe.}
proc deserialize*(s: string): Value {.gcsafe.}
proc deserialize_literal*(s: string): Value {.gcsafe.}
proc to_s*(self: Serialization): string

const
  TreeGeneTypeName = "_genetype"
  TreeGenePropsName = "_geneprops"
  TreeGeneChildrenName = "_genechildren"
  TreeArrayName = "_genearray"

proc new_gene_ref(path: string): Value =
  # Create (gene/ref "path")
  let gene = new_gene("gene/ref".to_symbol_value())
  gene.children.add(path.to_value())
  gene.to_gene_value()

# Serialize a value into a form that can be stored and later deserialized
proc serialize*(value: Value): Serialization =
  result = Serialization(
    references: initTable[string, Value](),
  )
  result.data = result.serialize(value)

proc serialize*(self: Serialization, value: Value): Value =
  case value.kind:
  of VkNil, VkBool, VkInt, VkFloat, VkChar:
    return value
  of VkString, VkSymbol:
    return value
  of VkArray:
    var arr_val = new_array_value()
    for item in array_data(value):
      array_data(arr_val).add(self.serialize(item))
    return arr_val
  of VkMap:
    let map = new_map_value()
    map_data(map) = initTable[Key, Value]()
    for k, v in map_data(value):
      map_data(map)[k] = self.serialize(v)
    return map
  of VkGene:
    let gene = new_gene(self.serialize(value.gene.type))
    for k, v in value.gene.props:
      gene.props[k] = self.serialize(v)
    for child in value.gene.children:
      gene.children.add(self.serialize(child))
    return gene.to_gene_value()
  of VkClass:
    return new_gene_ref(value.to_path())
  of VkFunction:
    return new_gene_ref(value.to_path())
  of VkInstance:
    # Create (gene/instance <class-ref> {props})
    let gene = new_gene("gene/instance".to_symbol_value())
    gene.children.add(new_gene_ref(value.instance_class.to_path()))
    
    let props = new_map_value()
    map_data(props) = initTable[Key, Value]()
    for k, v in value.instance_props:
      map_data(props)[k] = self.serialize(v)
    gene.children.add(props)
    
    return gene.to_gene_value()
  else:
    todo("serialize " & $value.kind)

# Fast literal checker: primitives, strings/symbols, arrays/maps/genes with literal children
proc is_literal_value*(v: Value): bool {.inline, gcsafe.} =
  var stack: seq[Value] = @[v]
  var seen_arrays: HashSet[ptr ArrayObj]
  var seen_maps: HashSet[ptr MapObj]
  var seen_genes: HashSet[ptr Gene]

  while stack.len > 0:
    let cur = stack.pop()
    case cur.kind:
    of VkVoid, VkNil, VkPlaceholder, VkBool, VkInt, VkFloat, VkChar,
       VkString, VkSymbol, VkComplexSymbol, VkByte, VkBytes, VkBin, VkBin64,
       VkDate, VkDateTime:
      continue
    of VkArray:
      let r = array_ptr(cur)
      if seen_arrays.contains(r): continue
      seen_arrays.incl(r)
      for item in r.arr: stack.add(item)
    of VkMap:
      let r = map_ptr(cur)
      if seen_maps.contains(r): continue
      seen_maps.incl(r)
      for _, val in r.map: stack.add(val)
    of VkGene:
      let gptr = cur.gene
      if seen_genes.contains(gptr): continue
      seen_genes.incl(gptr)
      if gptr.type != NIL:
        stack.add(gptr.type)
      for _, val in gptr.props: stack.add(val)
      for child in gptr.children: stack.add(child)
    else:
      return false
  true

# Serialize only literal values; reject unsupported kinds early.
#
# Thread messaging only supports "literal" values - primitives and containers
# with literal contents. This constraint exists because:
# 1. Functions/closures may reference thread-local state
# 2. Class/instance objects have complex object graphs
# 3. Thread/Future handles are thread-specific
#
# Allowed types: nil, bool, int, float, char, string, symbol, byte, bytes,
#                date, datetime, arrays/maps/genes with literal contents
# Not allowed: functions, classes, instances, threads, futures, namespaces, etc.
proc serialize_literal*(value: Value): Serialization {.gcsafe.} =
  if not is_literal_value(value):
    not_allowed("Thread message payload must be a literal value. Got " & $value.kind &
                ". Allowed: primitives (nil/bool/int/float/char/string/symbol/byte/bytes/date/datetime) " &
                "and containers (array/map/gene) with literal contents. " &
                "Not allowed: functions, classes, instances, threads, futures.")
  serialize(value)

proc deserialize_literal*(s: string): Value {.gcsafe.} =
  deserialize(s)

proc to_path*(self: Class): string =
  # For now, just return the class name
  # In the future, we can build a full path
  return self.name

# A path looks like
# Class C => "pkgP:modM:nsN/C" or just "nsN/C" or "C"
proc to_path*(self: Value): string =
  case self.kind:
  of VkClass:
    return self.ref.class.to_path()
  of VkFunction:
    # For now, just return the function name
    # TODO: Handle namespaced functions properly
    return self.ref.fn.name
  else:
    not_allowed("to_path " & $self.kind)

proc path_to_value*(path: string): Value =
  # Check if it's a namespaced path (e.g., "n/f")
  if "/" in path:
    let parts = path.split("/")
    if parts.len >= 2:
      # Handle nested namespace paths
      var current_ns: Namespace = nil
      var search_namespaces: seq[Namespace] = @[]
      
      # Add namespaces to search
      if App.app.global_ns.kind == VkNamespace:
        search_namespaces.add(App.app.global_ns.ref.ns)
      if VM != nil and VM.frame != nil and VM.frame.ns != nil:
        search_namespaces.add(VM.frame.ns)
      
      # Find the first namespace in the path
      let first_key = parts[0].to_key()
      for ns in search_namespaces:
        if ns.members.has_key(first_key):
          let ns_val = ns.members[first_key]
          if ns_val.kind == VkNamespace:
            current_ns = ns_val.ref.ns
            break
      
      if current_ns != nil:
        # Navigate through nested namespaces
        for i in 1..<parts.len-1:
          let key = parts[i].to_key()
          if current_ns.members.has_key(key):
            let val = current_ns.members[key]
            if val.kind == VkNamespace:
              current_ns = val.ref.ns
            else:
              # Not a namespace, can't continue
              break
          else:
            # Key not found
            current_ns = nil
            break
        
        # Look for the final item
        if current_ns != nil:
          let final_key = parts[^1].to_key()
          if current_ns.members.has_key(final_key):
            return current_ns.members[final_key]
  
  # Look in global namespace first
  let key = path.to_key()
  if App.app.global_ns.kind == VkNamespace and App.app.global_ns.ref.ns.members.has_key(key):
    return App.app.global_ns.ref.ns.members[key]
  
  # Also check if VM is running and has a current frame
  if VM != nil and VM.frame != nil and VM.frame.ns != nil:
    if VM.frame.ns.members.has_key(key):
      return VM.frame.ns.members[key]
  
  not_allowed("path_to_value: not found: " & path)

proc value_to_gene_str(self: Value): string

proc key_to_string(k: Key): string =
  let symbol_value = cast[Value](k)
  let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
  get_symbol(symbol_index.int)

proc is_tree_structural(value: Value): bool {.inline.} =
  value.kind in {VkMap, VkArray, VkGene}

proc split_tree_selector_path(path: string): seq[string] =
  if '\\' notin path:
    return path.split('/')

  result = @[]
  var part = ""
  var i = 0
  while i < path.len:
    if path[i] == '\\' and i + 1 < path.len and path[i + 1] == '/':
      part.add('/')
      i += 2
    elif path[i] == '/':
      result.add(part)
      part = ""
      inc(i)
    else:
      part.add(path[i])
      inc(i)
  result.add(part)

proc encode_path_segment(segment: string): string =
  encodeUrl(segment, usePlus = false)

proc decode_path_segment(segment: string): string =
  decodeUrl(segment, decodePlus = false)

proc tree_path_key(segments: openArray[string]): string =
  if segments.len == 0:
    return "/"

  var encoded: seq[string] = @[]
  for segment in segments:
    encoded.add(encode_path_segment(segment))
  encoded.join("/")

proc tree_path_display(segments: openArray[string]): string =
  if segments.len == 0:
    return "/"
  "/" & segments.join("/")

proc append_serialized_payload(result: var string, value: Value)

proc append_serialized_map(result: var string, values: Table[Key, Value]) =
  result.add("{")
  var first = true
  for k, v in values:
    if not first:
      result.add(" ")
    result.add("^")
    result.add(key_to_string(k))
    result.add(" ")
    append_serialized_payload(result, v)
    first = false
  result.add("}")

proc append_serialized_ref(result: var string, path: string) =
  result.add("(gene/ref ")
  result.add(json.escapeJson(path))
  result.add(")")

proc append_serialized_payload(result: var string, value: Value) =
  case value.kind:
  of VkNil:
    result.add("nil")
  of VkBool:
    result.add(if value == TRUE: "true" else: "false")
  of VkInt:
    result.add($value.to_int())
  of VkFloat:
    result.add($value.to_float())
  of VkChar:
    result.add("'")
    result.add($chr((value.raw and 0xFF).int))
    result.add("'")
  of VkString:
    result.add(json.escapeJson(value.str))
  of VkSymbol:
    result.add(value.str)
  of VkArray:
    result.add("[")
    for index, item in array_data(value):
      if index > 0:
        result.add(" ")
      append_serialized_payload(result, item)
    result.add("]")
  of VkMap:
    append_serialized_map(result, map_data(value))
  of VkGene:
    result.add("(")
    append_serialized_payload(result, value.gene.type)
    for k, v in value.gene.props:
      result.add(" ^")
      result.add(key_to_string(k))
      result.add(" ")
      append_serialized_payload(result, v)
    for child in value.gene.children:
      result.add(" ")
      append_serialized_payload(result, child)
    result.add(")")
  of VkClass, VkFunction:
    append_serialized_ref(result, value.to_path())
  of VkInstance:
    result.add("(gene/instance ")
    append_serialized_ref(result, value.instance_class.to_path())
    result.add(" ")
    append_serialized_map(result, value.instance_props)
    result.add(")")
  else:
    todo("serialize " & $value.kind)

proc value_to_serialized_text(value: Value): string =
  result = "(gene/serialization "
  append_serialized_payload(result, value)
  result.add(")")

proc tree_serialized_hash(value: Value): Hash

proc mix_tree_hash(result: var Hash, marker: string) {.inline.} =
  result = result !& hash(marker)

proc tree_serialized_hash(value: Value): Hash =
  var result_hash: Hash = 0
  case value.kind:
  of VkNil:
    result_hash.mix_tree_hash("nil")
  of VkBool:
    result_hash.mix_tree_hash(if value == TRUE: "true" else: "false")
  of VkInt:
    result_hash.mix_tree_hash("int")
    result_hash = result_hash !& hash(value.to_int())
  of VkFloat:
    result_hash.mix_tree_hash("float")
    result_hash = result_hash !& hash(value.to_float())
  of VkChar:
    result_hash.mix_tree_hash("char")
    result_hash = result_hash !& hash((value.raw and 0xFF).int)
  of VkString:
    result_hash.mix_tree_hash("string")
    result_hash = result_hash !& hash(value.str)
  of VkSymbol:
    result_hash.mix_tree_hash("symbol")
    result_hash = result_hash !& hash(value.str)
  of VkArray:
    result_hash.mix_tree_hash("array")
    for item in array_data(value):
      result_hash = result_hash !& tree_serialized_hash(item)
  of VkMap:
    result_hash.mix_tree_hash("map")
    for k, v in map_data(value):
      result_hash = result_hash !& hash(key_to_string(k))
      result_hash = result_hash !& tree_serialized_hash(v)
  of VkGene:
    result_hash.mix_tree_hash("gene")
    result_hash = result_hash !& tree_serialized_hash(value.gene.type)
    for k, v in value.gene.props:
      result_hash = result_hash !& hash(key_to_string(k))
      result_hash = result_hash !& tree_serialized_hash(v)
    for child in value.gene.children:
      result_hash = result_hash !& tree_serialized_hash(child)
  of VkClass:
    result_hash.mix_tree_hash("class")
    result_hash = result_hash !& hash(value.to_path())
  of VkFunction:
    result_hash.mix_tree_hash("function")
    result_hash = result_hash !& hash(value.to_path())
  of VkInstance:
    result_hash.mix_tree_hash("instance")
    result_hash = result_hash !& hash(value.instance_class.to_path())
    for k, v in value.instance_props:
      result_hash = result_hash !& hash(key_to_string(k))
      result_hash = result_hash !& tree_serialized_hash(v)
  else:
    todo("serialize " & $value.kind)
  !$result_hash

proc add_directory_node(options: var TreeWriteOptions, segments: openArray[string]) =
  options.directory_nodes.incl(tree_path_key(segments))

proc should_write_dir(options: TreeWriteOptions, segments: openArray[string]): bool =
  options.directory_nodes.contains(tree_path_key(segments))

proc parse_tree_selector(selector: Value): seq[string] =
  var parts: seq[string]
  case selector.kind
  of VkComplexSymbol:
    parts = selector.ref.csymbol
  of VkSelector:
    parts = @[""]
    for segment in selector.ref.selector_path:
      case segment.kind
      of VkString, VkSymbol:
        parts.add(segment.str)
      of VkInt:
        parts.add($segment.to_int())
      else:
        not_allowed("write_tree ^separate selectors only support string, symbol, and integer path segments")
  of VkString, VkSymbol:
    parts = split_tree_selector_path(selector.str)
  else:
    not_allowed("write_tree ^separate entries must be selectors, strings, or symbols")

  if parts.len > 0 and parts[0] == "self":
    parts[0] = ""

  if parts.len < 2 or parts[0] != "" or parts[^1] != "*":
    not_allowed("write_tree ^separate entries must be absolute child selectors ending with /*")

  if parts.len == 2:
    return @[]
  parts[1 .. ^2]

proc build_tree_write_options(separate_value: Value): TreeWriteOptions =
  result.directory_nodes = initHashSet[string]()
  if separate_value == NIL:
    return
  if separate_value.kind != VkArray:
    not_allowed("write_tree ^separate expects an array")

  for selector in array_data(separate_value):
    let parent_segments = parse_tree_selector(selector)
    for prefix_len in 0 .. parent_segments.len:
      result.add_directory_node(parent_segments[0 ..< prefix_len])

proc ensure_parent_dir(path: string) =
  let parent = parentDir(path)
  if parent.len > 0 and parent != ".":
    createDir(parent)

proc write_serialized_file(path: string, value: Value) =
  ensure_parent_dir(path)
  writeFile(path, value_to_serialized_text(value))

proc read_serialized_file(path: string): Value =
  deserialize(readFile(path))

proc remove_tree_dir(path: string) =
  if fileExists(path):
    removeFile(path)
    return
  if not dirExists(path):
    return

  for kind, child in walkDir(path):
    case kind
    of pcFile, pcLinkToFile:
      removeFile(child)
    of pcDir:
      remove_tree_dir(child)
    of pcLinkToDir:
      removeDir(child)
    else:
      discard
  removeDir(path)

proc remove_tree_base(path: string) =
  let file_path = path & ".gene"
  if fileExists(file_path):
    removeFile(file_path)
  if dirExists(path):
    remove_tree_dir(path)

proc write_tree_node(path: string, value: Value, node_segments: seq[string], options: TreeWriteOptions, known_map = false)
proc write_tree_dir(path: string, value: Value, node_segments: seq[string], options: TreeWriteOptions, known_map = false)
proc read_tree_path(path: string): Value
proc read_tree_root_path(path: string): Value
proc read_tree_dir(path: string): Value
proc read_known_map_dir(path: string): Value
proc read_array_dir(path: string): Value
proc read_gene_dir(path: string): Value
proc list_tree_dir_entries(path: string): seq[(PathComponent, string)]
proc resolve_tree_named_child(path: string, child_name: string): Value
proc can_decode_as_array_dir(path: string): bool

proc make_array_child_id(value: Value, used_ids: var Table[string, int]): string =
  let base = "v" & toHex(cast[uint64](tree_serialized_hash(value)), 12)
  let next_count = used_ids.getOrDefault(base, 0) + 1
  used_ids[base] = next_count
  if next_count == 1:
    base
  else:
    base & "-" & $next_count

proc write_map_dir(path: string, map_value: Value, node_segments: seq[string], options: TreeWriteOptions, allow_root_markers: bool) =
  createDir(path)
  var keys: seq[string] = @[]
  var key_values = initTable[string, Value]()
  for k, v in map_data(map_value):
    let key_name = key_to_string(k)
    if not allow_root_markers and key_name == TreeGeneTypeName:
      not_allowed("Exploded generic map roots cannot use reserved entry name: " & key_name)
    keys.add(key_name)
    key_values[key_name] = v

  keys.sort()
  for key_name in keys:
    let child = key_values[key_name]
    let encoded = encode_path_segment(key_name)
    let child_segments = node_segments & @[key_name]
    write_tree_node(joinPath(path, encoded), child, child_segments, options, false)

proc write_array_dir(path: string, array_value: Value, node_segments: seq[string], options: TreeWriteOptions) =
  createDir(path)
  var order = new_array_value()
  var used_ids = initTable[string, int]()
  for index, child in array_data(array_value):
    let child_id = make_array_child_id(child, used_ids)
    array_data(order).add(child_id.to_value())
    let child_segments = node_segments & @[$index]
    write_tree_node(joinPath(path, child_id), child, child_segments, options, false)
  write_serialized_file(joinPath(path, TreeArrayName & ".gene"), order)

proc write_gene_dir(path: string, gene_value: Value, node_segments: seq[string], options: TreeWriteOptions) =
  createDir(path)
  let type_segments = node_segments & @[TreeGeneTypeName]
  write_tree_node(joinPath(path, TreeGeneTypeName), gene_value.gene.type, type_segments, options, false)

  let props_segments = node_segments & @[TreeGenePropsName]
  if gene_value.gene.props.len > 0 or should_write_dir(options, props_segments):
    let props_path = joinPath(path, TreeGenePropsName)
    var props_value = new_map_value()
    map_data(props_value) = initTable[Key, Value]()
    for k, v in gene_value.gene.props:
      map_data(props_value)[k] = v
    write_map_dir(props_path, props_value, props_segments, options, true)

  let children_segments = node_segments & @[TreeGeneChildrenName]
  if gene_value.gene.children.len > 0 or should_write_dir(options, children_segments):
    let children_path = joinPath(path, TreeGeneChildrenName)
    var children_value = new_array_value()
    for child in gene_value.gene.children:
      array_data(children_value).add(child)
    write_array_dir(children_path, children_value, children_segments, options)

proc write_tree_node(path: string, value: Value, node_segments: seq[string], options: TreeWriteOptions, known_map = false) =
  remove_tree_base(path)

  if should_write_dir(options, node_segments):
    if not is_tree_structural(value):
      not_allowed("write_tree ^separate targets a non-structural value at " & tree_path_display(node_segments))
    write_tree_dir(path, value, node_segments, options, known_map)
  else:
    write_serialized_file(path & ".gene", value)

proc write_tree_dir(path: string, value: Value, node_segments: seq[string], options: TreeWriteOptions, known_map = false) =
  case value.kind
  of VkMap:
    write_map_dir(path, value, node_segments, options, known_map)
  of VkArray:
    write_array_dir(path, value, node_segments, options)
  of VkGene:
    write_gene_dir(path, value, node_segments, options)
  else:
    not_allowed("Directory tree serialization requires a Map, Array, or Gene root")

proc read_known_map_dir(path: string): Value =
  result = new_map_value()
  map_data(result) = initTable[Key, Value]()
  for (kind, entry) in list_tree_dir_entries(path):
    case kind
    of pcFile:
      if not entry.endsWith(".gene"):
        continue
      let decoded = decode_path_segment(splitFile(entry).name)
      map_data(result)[decoded.to_key()] = read_serialized_file(joinPath(path, entry))
    of pcDir:
      let decoded = decode_path_segment(entry)
      map_data(result)[decoded.to_key()] = read_tree_path(joinPath(path, entry))
    else:
      discard

proc list_tree_dir_entries(path: string): seq[(PathComponent, string)] =
  for kind, entry in walkDir(path, relative = true):
    result.add((kind, entry))
  result.sort(proc(a, b: (PathComponent, string)): int = cmp(a[1], b[1]))

proc resolve_tree_named_child(path: string, child_name: string): Value =
  let inline_path = joinPath(path, child_name & ".gene")
  let dir_path = joinPath(path, child_name)
  let has_inline = fileExists(inline_path)
  let has_dir = dirExists(dir_path)
  if has_inline and has_dir:
    not_allowed("Filesystem tree child is ambiguous, both file and directory exist: " & joinPath(path, child_name))
  if has_inline:
    return read_serialized_file(inline_path)
  if has_dir:
    return read_tree_dir(dir_path)
  not_allowed("Filesystem tree child not found: " & joinPath(path, child_name))

proc can_decode_as_array_dir(path: string): bool =
  let manifest_path = joinPath(path, TreeArrayName & ".gene")
  if not fileExists(manifest_path):
    return false

  let manifest = read_serialized_file(manifest_path)
  if manifest.kind != VkArray:
    return false

  var child_ids = initHashSet[string]()
  for item in array_data(manifest):
    if item.kind != VkString:
      return false
    let child_id = item.str
    if child_ids.contains(child_id):
      return false
    child_ids.incl(child_id)

  for (kind, entry) in list_tree_dir_entries(path):
    case kind
    of pcFile:
      if not entry.endsWith(".gene"):
        continue
      let entry_name = splitFile(entry).name
      if entry_name == TreeArrayName:
        continue
      if not child_ids.contains(entry_name):
        return false
    of pcDir:
      if not child_ids.contains(entry):
        return false
    else:
      discard

  for child_id in child_ids:
    let inline_path = joinPath(path, child_id & ".gene")
    let dir_path = joinPath(path, child_id)
    let has_inline = fileExists(inline_path)
    let has_dir = dirExists(dir_path)
    if has_inline == has_dir:
      return false

  true

proc read_array_dir(path: string): Value =
  let order_path = joinPath(path, TreeArrayName & ".gene")
  if not fileExists(order_path):
    not_allowed("Exploded array is missing " & TreeArrayName & ".gene: " & path)

  let order = read_serialized_file(order_path)
  if order.kind != VkArray:
    not_allowed(TreeArrayName & ".gene must contain an array of child ids")

  result = new_array_value()
  for item in array_data(order):
    if item.kind != VkString:
      not_allowed(TreeArrayName & ".gene child ids must be strings")
    let child_id = item.str
    let inline_path = joinPath(path, child_id & ".gene")
    let dir_path = joinPath(path, child_id)
    if fileExists(inline_path):
      array_data(result).add(read_serialized_file(inline_path))
    elif dirExists(dir_path):
      array_data(result).add(read_tree_dir(dir_path))
    else:
      not_allowed("Missing exploded array child: " & child_id)

proc read_gene_dir(path: string): Value =
  let type_file_path = joinPath(path, TreeGeneTypeName & ".gene")
  let type_dir_path = joinPath(path, TreeGeneTypeName)
  if not fileExists(type_file_path) and not dirExists(type_dir_path):
    not_allowed("Exploded Gene value is missing " & TreeGeneTypeName & ": " & path)

  let gene = new_gene(resolve_tree_named_child(path, TreeGeneTypeName))

  let props_path = joinPath(path, TreeGenePropsName)
  if dirExists(props_path):
    let props_value = read_known_map_dir(props_path)
    for k, v in map_data(props_value):
      gene.props[k] = v

  let children_path = joinPath(path, TreeGeneChildrenName)
  if dirExists(children_path):
    let children_value = read_array_dir(children_path)
    for child in array_data(children_value):
      gene.children.add(child)

  gene.to_gene_value()

proc read_tree_dir(path: string): Value =
  let type_file_path = joinPath(path, TreeGeneTypeName & ".gene")
  let type_dir_path = joinPath(path, TreeGeneTypeName)
  if fileExists(type_file_path) or dirExists(type_dir_path):
    return read_gene_dir(path)

  if can_decode_as_array_dir(path):
    return read_array_dir(path)

  read_known_map_dir(path)

proc read_tree_path(path: string): Value =
  if fileExists(path):
    return read_serialized_file(path)
  if dirExists(path):
    return read_tree_dir(path)
  not_allowed("Filesystem tree path not found: " & path)

proc read_tree_root_path(path: string): Value =
  if path.endsWith(".gene"):
    return read_tree_path(path)

  let inline_path = path & ".gene"
  let has_inline = fileExists(inline_path)
  let has_dir = dirExists(path)

  if has_inline and has_dir:
    not_allowed("Filesystem tree root is ambiguous, both file and directory exist: " & path)
  if has_inline:
    return read_serialized_file(inline_path)
  if has_dir:
    return read_tree_dir(path)
  read_tree_path(path)

proc to_s*(self: Serialization): string =
  result = value_to_serialized_text(self.data)

proc value_to_gene_str(self: Value): string =
  case self.kind:
  of VkNil:
    result = "nil"
  of VkBool:
    result = if self == TRUE: "true" else: "false"
  of VkInt:
    result = $self.to_int()
  of VkFloat:
    result = $self.to_float()
  of VkChar:
    # Extract char from NaN-boxed value
    result = "'" & $chr((self.raw and 0xFF).int) & "'"
  of VkString:
    result = json.escapeJson(self.str)
  of VkSymbol:
    result = self.str
  of VkArray:
    result = "["
    for i, v in array_data(self):
      if i > 0:
        result &= " "
      result &= value_to_gene_str(v)
    result &= "]"
  of VkMap:
    result = "{"
    var first = true
    for k, v in map_data(self):
      if not first:
        result &= " "
      # k is a Key (distinct int64), which is a packed symbol value
      # Extract the symbol index from the packed value
      let symbol_value = cast[Value](k)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      let key_str = get_symbol(symbol_index.int)
      result &= "^" & key_str
      result &= " "
      result &= value_to_gene_str(v)
      first = false
    result &= "}"
  of VkGene:
    result = "("
    result &= value_to_gene_str(self.gene.type)
    # Add properties
    for k, v in self.gene.props:
      let symbol_value = cast[Value](k)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= " ^" & get_symbol(symbol_index.int) & " " & value_to_gene_str(v)
    # Add children
    for child in self.gene.children:
      result &= " " & value_to_gene_str(child)
    result &= ")"
  else:
    result = $self  # Fallback to default string representation

#################### Deserialization #############

proc deserialize*(self: Serialization, value: Value): Value {.gcsafe.}

proc deref*(self: Serialization, s: string): Value =
  path_to_value(s)

proc deserialize*(s: string): Value =
  var ser = Serialization(
    references: initTable[string, Value](),
  )
  ser.deserialize(read_all(s)[0])

proc deserialize*(self: Serialization, value: Value): Value =
  case value.kind:
  of VkGene:
    # Check if it's a special gene type
    var type_str: string
    if value.gene.type.kind == VkSymbol:
      type_str = value.gene.type.str
    elif value.gene.type.kind == VkComplexSymbol:
      type_str = value.gene.type.ref.csymbol.join("/")
    else:
      # Regular gene - deserialize recursively
      let gene = new_gene(self.deserialize(value.gene.type))
      for k, v in value.gene.props:
        gene.props[k] = self.deserialize(v)
      for child in value.gene.children:
        gene.children.add(self.deserialize(child))
      return gene.to_gene_value()
    
    # Handle special gene types
    case type_str:
    of "gene/serialization":
      if value.gene.children.len > 0:
        return self.deserialize(value.gene.children[0])
      else:
        return NIL
    of "gene/ref":
      if value.gene.children.len > 0:
        return self.deref(value.gene.children[0].str)
      else:
        return NIL
    of "gene/instance":
        if value.gene.children.len >= 2:
          var class_ref = self.deserialize(value.gene.children[0])
          if class_ref.kind != VkClass:
            not_allowed("gene/instance expects class reference")
          
          var instance = new_instance_value(class_ref.ref.class)
          
          # Deserialize properties
          let props = value.gene.children[1]
          if props.kind == VkMap:
            for k, v in map_data(props):
              instance_props(instance)[k] = self.deserialize(v)
          
          return instance
        else:
          return NIL
    else:
      # Regular gene - deserialize recursively
      let gene = new_gene(self.deserialize(value.gene.type))
      for k, v in value.gene.props:
        gene.props[k] = self.deserialize(v)
      for child in value.gene.children:
        gene.children.add(self.deserialize(child))
      return gene.to_gene_value()
  else:
    # Simple values serialize to themselves
    return value

# VM integration functions
proc resolve_symbol_in_caller(caller_frame: Frame, name: string): Value =
  let key = name.to_key()

  if caller_frame != nil and caller_frame.scope != nil and caller_frame.scope.tracker != nil:
    let found = caller_frame.scope.tracker.locate(key)
    if found.local_index >= 0:
      var scope = caller_frame.scope
      var parent_index = found.parent_index
      while parent_index > 0:
        parent_index.dec()
        scope = scope.parent
      if scope != nil and found.local_index < scope.members.len:
        return scope.members[found.local_index]

  if caller_frame != nil and caller_frame.ns != nil:
    let ns_value = caller_frame.ns[key]
    if ns_value != NIL:
      return ns_value

  let global_value = App.app.global_ns.ref.ns.members.getOrDefault(key, NIL)
  if global_value != NIL:
    return global_value

  App.app.gene_ns.ref.ns.members.getOrDefault(key, NIL)

proc eval_in_caller_context(vm: ptr VirtualMachine, expr: Value, caller_frame: Frame): Value =
  discard vm
  case expr.kind
  of VkString, VkInt, VkFloat, VkBool, VkNil, VkChar, VkComplexSymbol:
    return expr
  of VkSymbol:
    let resolved = resolve_symbol_in_caller(caller_frame, expr.str)
    if resolved == NIL:
      not_allowed("Unknown symbol in caller context: " & expr.str)
    return resolved
  of VkArray:
    result = new_array_value()
    for item in array_data(expr):
      array_data(result).add(eval_in_caller_context(vm, item, caller_frame))
  of VkMap:
    result = new_map_value()
    for k, v in map_data(expr):
      map_data(result)[k] = eval_in_caller_context(vm, v, caller_frame)
  of VkGene:
    let gene = new_gene(eval_in_caller_context(vm, expr.gene.type, caller_frame))
    for k, v in expr.gene.props:
      gene.props[k] = eval_in_caller_context(vm, v, caller_frame)
    for child in expr.gene.children:
      gene.children.add(eval_in_caller_context(vm, child, caller_frame))
    return gene.to_gene_value()
  of VkQuote:
    return expr.ref.quote
  else:
    not_allowed("write_tree macro arguments must be literals or symbols")

proc write_tree_root(path: string, value: Value, options: TreeWriteOptions) =
  if path.endsWith(".gene"):
    if options.directory_nodes.len > 0:
      not_allowed("write_tree cannot use a .gene path when ^separate requires directories")
    write_serialized_file(path, value)
  else:
    remove_tree_base(path)
    if should_write_dir(options, @[]):
      if not is_tree_structural(value):
        not_allowed("write_tree ^separate targets a non-structural root value")
      write_tree_dir(path, value, @[], options, false)
    else:
      write_serialized_file(path & ".gene", value)

proc vm_serialize(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    if arg_count != 1:
      not_allowed("serialize expects 1 argument")

    let value = get_positional_arg(args, 0, has_keyword_args)
    return value_to_serialized_text(value).to_value()

proc vm_deserialize(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    if arg_count != 1:
      not_allowed("deserialize expects 1 argument")

    let s = get_positional_arg(args, 0, has_keyword_args).str
    return deserialize(s)

proc vm_write_tree_macro(vm: ptr VirtualMachine, gene_value: Value, caller_frame: Frame): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    when defined(gene_wasm):
      not_allowed("write_tree is not supported in gene_wasm")
    else:
      if gene_value.kind != VkGene or gene_value.gene.children.len != 2:
        not_allowed("write_tree expects 2 arguments")

      let path_arg = eval_in_caller_context(vm, gene_value.gene.children[0], caller_frame)
      if path_arg.kind != VkString:
        not_allowed("write_tree expects a string path")

      let value = eval_in_caller_context(vm, gene_value.gene.children[1], caller_frame)
      let separate_value = gene_value.gene.props.getOrDefault("separate".to_key(), NIL)
      let options = build_tree_write_options(separate_value)
      write_tree_root(path_arg.str, value, options)
      NIL

proc vm_read_tree(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    when defined(gene_wasm):
      not_allowed("read_tree is not supported in gene_wasm")
    else:
      if get_positional_count(arg_count, has_keyword_args) != 1:
        not_allowed("read_tree expects 1 argument")

      let path_arg = get_positional_arg(args, 0, has_keyword_args)
      if path_arg.kind != VkString:
        not_allowed("read_tree expects a string path")

      read_tree_root_path(path_arg.str)

# Initialize the serdes namespace
proc init_serdes*() =
  let serdes_ns = new_namespace("serdes")
  serdes_ns["serialize".to_key()] = NativeFn(vm_serialize).to_value()
  serdes_ns["deserialize".to_key()] = NativeFn(vm_deserialize).to_value()
  var write_tree_ref = new_ref(VkNativeMacro)
  write_tree_ref.native_macro = vm_write_tree_macro
  serdes_ns["write_tree".to_key()] = write_tree_ref.to_ref_value()
  serdes_ns["read_tree".to_key()] = NativeFn(vm_read_tree).to_value()
  App.app.gene_ns.ref.ns["serdes".to_key()] = serdes_ns.to_value()
