## Module compilation: compile_import, compile_export.
## Included from compiler.nim — shares its scope (emit, compile, etc.).

proc compile_import(self: Compiler, gene: ptr Gene) =
  # (import a b from "module")
  # (import from "module" a b)
  # (import a:alias b from "module")
  # (import n/f from "module")
  # (import n/[one two] from "module")

  # Imports are compile-time constructs in module scope.
  # Runtime/nested imports must go through (comptime ...) expansion.
  if not self.preserve_root_scope:
    not_allowed("import is compile-time only; place imports at module top level or emit them from (comptime ...)")

  # echo "DEBUG: compile_import called for ", gene
  # echo "DEBUG: gene.children = ", gene.children
  # echo "DEBUG: gene.props = ", gene.props

  # Record module import metadata when compiling a module
  if self.preserve_root_scope:
    var module_path = ""
    var i = 0
    while i + 1 < gene.children.len:
      let child = gene.children[i]
      if child.kind == VkSymbol and child.str == "from":
        let next = gene.children[i + 1]
        if next.kind == VkString:
          module_path = next.str
        break
      i.inc()
    if module_path.len > 0:
      var exists = false
      for item in self.output.module_imports:
        if item == module_path:
          exists = true
          break
      if not exists:
        self.output.module_imports.add(module_path)

  # Compile a gene value for the import, but with "import" as a symbol type
  self.emit(Instruction(kind: IkGeneStart))
  self.emit(Instruction(kind: IkPushValue, arg0: "import".to_symbol_value()))
  self.emit(Instruction(kind: IkGeneSetType))

  # Compile the props
  for k, v in gene.props:
    self.emit(Instruction(kind: IkPushValue, arg0: v))
    self.emit(Instruction(kind: IkGeneSetProp, arg0: k))

  # Compile the children - they should be treated as quoted values
  for child in gene.children:
    # Import arguments are data, not code to execute
    # So compile them as literal values
    case child.kind:
    of VkSymbol, VkString:
      self.emit(Instruction(kind: IkPushValue, arg0: child))
    of VkComplexSymbol:
      # Handle n/f syntax
      self.emit(Instruction(kind: IkPushValue, arg0: child))
    of VkArray:
      # Handle [one two] part of n/[one two]
      self.emit(Instruction(kind: IkPushValue, arg0: child))
    of VkGene:
      # Handle complex forms like a:alias or n/[a b]
      self.compile_gene_default(child.gene)
    else:
      self.compile(child)
    self.emit(Instruction(kind: IkGeneAddChild))

  self.emit(Instruction(kind: IkGeneEnd))
  self.emit(Instruction(kind: IkImport))

proc compile_export(self: Compiler, gene: ptr Gene) =
  # (export [a b]) or (export a b)
  proc record_export(name: string) =
    if not self.preserve_root_scope or name.len == 0:
      return
    var exists = false
    for item in self.output.module_exports:
      if item == name:
        exists = true
        break
    if not exists:
      self.output.module_exports.add(name)

  var items: seq[Value] = @[]
  if gene.children.len == 1 and gene.children[0].kind == VkArray:
    items = array_data(gene.children[0])
  else:
    items = gene.children

  if items.len == 0:
    not_allowed("export expects at least one name")

  let export_list = new_array_value()
  for item in items:
    case item.kind
    of VkSymbol:
      if item.str.contains("/"):
        not_allowed("export names must be simple symbols")
      array_data(export_list).add(item)
      record_export(item.str)
    of VkString:
      if item.str.contains("/"):
        not_allowed("export names must be simple strings")
      array_data(export_list).add(item)
      record_export(item.str)
    else:
      not_allowed("export names must be symbols or strings")

  self.emit(Instruction(kind: IkExport, arg0: export_list))
