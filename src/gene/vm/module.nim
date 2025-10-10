import tables, strutils
import std/hashes
import os

import ../types
import ../parser
import ../compiler
when not defined(noExtensions):
  import ./extension

type
  ImportItem* = object
    name*: string
    alias*: string
    children*: seq[string]  # For nested imports like n/[a b]

# Global module cache
var ModuleCache* = initTable[string, Namespace]()

proc split_import_path(name: string): seq[string] =
  ## Split an import path like "genex/http/*" into parts.
  if name.len == 0:
    return @[]
  result = name.split("/")

proc extension_library_path(name: string): string =
  ## Determine default path for a compiled extension library.
  when defined(windows):
    result = "build" / ("lib" & name & ".dll")
  elif defined(macosx):
    result = "build" / ("lib" & name & ".dylib")
  else:
    result = "build" / ("lib" & name & ".so")

proc ensure_genex_extension(vm: VirtualMachine, part: string): Value =
  ## Ensure a genex extension is loaded when accessing genex/<part>.
  if App == NIL or App.kind != VkApplication:
    return NIL
  if App.app.genex_ns.kind != VkNamespace:
    return NIL

  let key = part.to_key()
  var member = App.app.genex_ns.ref.ns.members.getOrDefault(key, NIL)

  if member == NIL:
    when not defined(noExtensions):
      let ext_path = extension_library_path(part)
      if fileExists(ext_path):
        try:
          let ext_ns = load_extension(vm, ext_path)
          if ext_ns != nil:
            member = ext_ns.to_value()
            App.app.genex_ns.ref.ns.members[key] = member
        except CatchableError:
          discard
    # Even if extension loading failed, keep NIL to prevent repeated attempts
  return member

proc resolve_from_root(vm: VirtualMachine, root: Value, parts: seq[string]): Value =
  ## Resolve a path against a root namespace value.
  if parts.len == 0:
    return root

  var current = root
  for part in parts:
    if part.len == 0:
      continue
    if current.kind != VkNamespace:
      return NIL
    let key = part.to_key()
    var next = current.ref.ns.members.getOrDefault(key, NIL)
    if next == NIL and current.kind == VkNamespace and App != NIL and App.kind == VkApplication and App.app.genex_ns.kind == VkNamespace and current.ref.ns == App.app.genex_ns.ref.ns:
      next = ensure_genex_extension(vm, part)
      if next == NIL:
        current.ref.ns.members[key] = NIL
    if next == NIL:
      return NIL
    current = next

  return current

proc import_from_namespace(vm: VirtualMachine, items: seq[ImportItem]): bool =
  ## Try to handle imports targeting known namespaces like gene/* or genex/*.
  var handled = false

  for item in items:
    let parts = split_import_path(item.name)
    if parts.len == 0:
      continue

    var root: Value
    var start_index = 0

    case parts[0]
    of "gene":
      if App == NIL or App.kind != VkApplication:
        continue
      root = App.app.gene_ns
      start_index = 1
    of "genex":
      if App == NIL or App.kind != VkApplication:
        continue
      root = App.app.genex_ns
      start_index = 1
    of "global":
      if App == NIL or App.kind != VkApplication:
        continue
      root = App.app.global_ns
      start_index = 1
    else:
      continue  # Delegate to module loader for unknown roots

    if start_index > parts.len:
      continue

    if parts.len > start_index and parts[^1] == "*":
      let ns_value = resolve_from_root(vm, root, parts[start_index ..< parts.len - 1])
      if ns_value.kind != VkNamespace:
        not_allowed("Cannot import '*' from non-namespace '" & item.name & "'")

      for key, value in ns_value.ref.ns.members:
        if value != NIL:
          vm.frame.ns.members[key] = value
      handled = true
      continue

    let resolved = resolve_from_root(vm, root, parts[start_index ..< parts.len])
    if resolved == NIL:
      not_allowed("Symbol '" & item.name & "' not found in namespace")

    let import_name = if item.alias.len > 0: item.alias else: parts[^1]
    vm.frame.ns.members[import_name.to_key()] = resolved
    handled = true

  return handled

proc parse_import_statement*(gene: ptr Gene): tuple[module_path: string, imports: seq[ImportItem]] =
  ## Parse import statement into module path and list of imports
  var module_path = ""
  var imports: seq[ImportItem] = @[]
  var i = 0
  
  while i < gene.children.len:
    let child = gene.children[i]
    
    if child.kind == VkSymbol and child.str == "from":
      # Handle "from module" syntax
      if i + 1 < gene.children.len and gene.children[i + 1].kind == VkString:
        module_path = gene.children[i + 1].str
        i += 2
        continue
      else:
        not_allowed("'from' must be followed by a string module path")
    
    # Parse import items
    case child.kind:
      of VkSymbol:
        let s = child.str
        var item: ImportItem
        
        # Check if symbol contains : for alias syntax (a:alias)
        let colonPos = s.find(':')
        if colonPos > 0 and colonPos < s.len - 1:
          # This is a:alias syntax
          item.name = s[0..<colonPos]
          item.alias = s[colonPos+1..^1]
        else:
          item.name = s
          
          # Check for alias syntax (a:b) as separate gene
          if i + 1 < gene.children.len and gene.children[i + 1].kind == VkGene:
            let alias_gene = gene.children[i + 1].gene
            if alias_gene.type.kind == VkSymbol and alias_gene.type.str == ":" and
               alias_gene.children.len == 1 and alias_gene.children[0].kind == VkSymbol:
              item.alias = alias_gene.children[0].str
              i += 1
        
        imports.add(item)
      
      of VkComplexSymbol:
        # Handle n/f or n/ followed by array
        let parts = child.ref.csymbol
        if parts.len > 0:
          # Check if this is n/ followed by an array [a b]
          if parts[^1] == "" and i + 1 < gene.children.len and gene.children[i + 1].kind == VkArray:
            # This is n/[a b] syntax
            let prefix = parts[0..^2].join("/")
            i += 1  # Move to the array
            let arr = gene.children[i].ref.arr
            
            for sub_child in arr:
              if sub_child.kind == VkSymbol:
                let s = sub_child.str
                var item: ImportItem
                
                # Check for alias in symbol
                let colonPos = s.find(':')
                if colonPos > 0 and colonPos < s.len - 1:
                  item.name = prefix & "/" & s[0..<colonPos]
                  item.alias = s[colonPos+1..^1]
                else:
                  item.name = prefix & "/" & s
                
                imports.add(item)
              elif sub_child.kind == VkGene:
                # Could be a:alias inside the brackets
                let sub_g = sub_child.gene
                if sub_g.type.kind == VkSymbol and sub_g.children.len == 1 and
                   sub_g.children[0].kind == VkSymbol:
                  var item = ImportItem(
                    name: prefix & "/" & sub_g.type.str,
                    alias: sub_g.children[0].str
                  )
                  imports.add(item)
          else:
            # Regular n/f syntax
            let fullPath = parts.join("/")
            var item: ImportItem
            
            # Check if last part contains : for alias syntax
            let colonPos = fullPath.find(':')
            if colonPos > 0 and colonPos < fullPath.len - 1:
              # This is n/f:alias syntax
              item.name = fullPath[0..<colonPos]
              item.alias = fullPath[colonPos+1..^1]
            else:
              item.name = fullPath
              
              # Check for alias as separate gene
              if i + 1 < gene.children.len and gene.children[i + 1].kind == VkGene:
                let alias_gene = gene.children[i + 1].gene
                if alias_gene.type.kind == VkSymbol and alias_gene.type.str == ":" and
                   alias_gene.children.len == 1 and alias_gene.children[0].kind == VkSymbol:
                  item.alias = alias_gene.children[0].str
                  i += 1
            
            imports.add(item)
      
      of VkGene:
        # Could be n/[a b] syntax or other complex forms
        let g = child.gene
        if g.type.kind == VkComplexSymbol:
          let parts = g.type.ref.csymbol
          if parts.len >= 2 and g.children.len > 0:
            # This is n/[a b] syntax
            let prefix = parts[0..^2].join("/")
            for sub_child in g.children:
              if sub_child.kind == VkSymbol:
                var item = ImportItem(name: prefix & "/" & sub_child.str)
                imports.add(item)
              elif sub_child.kind == VkGene:
                # Could be a:alias inside the brackets
                let sub_g = sub_child.gene
                if sub_g.type.kind == VkSymbol and sub_g.children.len == 1 and
                   sub_g.children[0].kind == VkSymbol:
                  var item = ImportItem(
                    name: prefix & "/" & sub_g.type.str,
                    alias: sub_g.children[0].str
                  )
                  imports.add(item)
        else:
          not_allowed("Invalid import syntax: " & $child)
      
      else:
        not_allowed("Invalid import item type: " & $child.kind)
    
    i += 1
  
  return (module_path, imports)

proc compile_module*(path: string): CompilationUnit =
  ## Compile a module from file and return its compilation unit
  # Read module file
  var code: string
  var actual_path = path
  
  # Try with .gene extension if not present
  if not path.endsWith(".gene"):
    actual_path = path & ".gene"
  
  try:
    code = readFile(actual_path)
  except IOError as e:
    # Try without extension if .gene failed
    if actual_path != path:
      try:
        code = readFile(path)
      except IOError:
        not_allowed("Failed to read module '" & path & "': " & e.msg)
    else:
      not_allowed("Failed to read module '" & path & "': " & e.msg)
  
  # Parse the module code
  var parser = new_parser()
  let parsed = parser.read_all(code)
  
  # Use the standard compile function
  return compile(parsed)

proc load_module*(vm: VirtualMachine, path: string): Namespace =
  ## Load a module from file and return its namespace
  # Check cache first
  if ModuleCache.hasKey(path):
    return ModuleCache[path]
  
  # Create namespace for module
  let module_ns = new_namespace(path)
  module_ns.members["__is_main__".to_key()] = FALSE
  module_ns.members["__module_name__".to_key()] = path.to_value()
  
  # Compile the module to ensure it's valid
  discard compile_module(path)
  
  # The VM will execute this module when needed
  # For now, just cache the empty namespace
  # The actual execution will happen when the import is processed
  
  # Cache the module
  ModuleCache[path] = module_ns
  
  return module_ns

proc resolve_import_value*(ns: Namespace, path: string): Value =
  ## Resolve a value from a namespace given a path like "n/f"
  let parts = path.split("/")
  var current_ns = ns
  var final_value = NIL
  
  for i, part in parts:
    let key = part.to_key()
    if not current_ns.members.hasKey(key):
      not_allowed("Symbol '" & part & "' not found in namespace")
    
    let value = current_ns.members[key]
    
    if i == parts.len - 1:
      # Last part - this is our result
      final_value = value
    else:
      # Intermediate part - must be a namespace
      if value.kind != VkNamespace:
        not_allowed("'" & part & "' is not a namespace")
      current_ns = value.ref.ns
  
  return final_value

proc execute_module*(vm: VirtualMachine, path: string, module_ns: Namespace): Value =
  ## Execute a module in its namespace context
  # This will be called from vm.nim where exec is available
  raise new_exception(types.Exception, "execute_module should be overridden by vm.nim")

proc handle_import*(vm: VirtualMachine, import_gene: ptr Gene): tuple[path: string, imports: seq[ImportItem], ns: Namespace, is_native: bool, handled: bool] =
  ## Parse import statement and prepare for execution
  let (module_path, imports) = parse_import_statement(import_gene)
  
  if module_path == "":
    if import_from_namespace(vm, imports):
      return ("", @[], nil, false, true)
    else:
      not_allowed("Module path not specified in import statement")
  
  # Check if this is a native extension
  var is_native = false
  if "native".to_key() in import_gene.props:
    is_native = import_gene.props["native".to_key()].to_bool()
  
  # Check cache first
  if ModuleCache.hasKey(module_path):
    let module_ns = ModuleCache[module_path]
    # Import requested symbols
    for item in imports:
      let value = resolve_import_value(module_ns, item.name)
      
      # Determine the name to import as
      let import_name = if item.alias != "": 
        item.alias 
      else:
        # Use the last part of the path
        let parts = item.name.split("/")
        parts[^1]
      
      # Add to current namespace
      vm.frame.ns.members[import_name.to_key()] = value
    return (module_path, imports, module_ns, is_native, false)
  
  # Module not cached, need to compile and execute it (or load as native)
  let module_ns = new_namespace(module_path)
  module_ns.members["__is_main__".to_key()] = FALSE
  module_ns.members["__module_name__".to_key()] = module_path.to_value()
  return (module_path, imports, module_ns, is_native, false)
