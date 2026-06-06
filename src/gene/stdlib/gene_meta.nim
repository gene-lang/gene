import tables

import ../types
import ./classes

proc init_gene_and_meta_classes*(object_class: Class) =
  var r: ptr Reference
  let gene_class = new_class("Gene")
  gene_class.parent = object_class
  gene_class.def_native_method("to_s", object_to_s_method)
  r = new_ref(VkClass)
  r.class = gene_class
  App.app.gene_class = r.to_ref_value()
  App.app.gene_ns.ns["Gene".to_key()] = App.app.gene_class
  App.app.global_ns.ns["Gene".to_key()] = App.app.gene_class

  proc gene_type_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Gene.type requires self")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.type must be called on a gene")
    gene_val.gene.type

  gene_class.def_native_method("type", gene_type_method)

  proc gene_props_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Gene.props requires self")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.props must be called on a gene")
    let result_ref = new_map_value()
    for key, value in gene_val.gene.props:
      map_data(result_ref)[key] = value
    result_ref

  gene_class.def_native_method("props", gene_props_method)

  proc gene_children_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Gene.children requires self")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.children must be called on a gene")
    var result_ref = new_array_value()
    for child in gene_val.gene.children:
      array_data(result_ref).add(child)
    result_ref

  gene_class.def_native_method("children", gene_children_method)

  proc gene_immutable_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Gene.immutable? requires self")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("immutable? must be called on a gene")
    gene_is_frozen(gene_val).to_value()

  gene_class.def_native_method("immutable?", gene_immutable_method)

  # Gene property (member) APIs
  proc gene_has_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Gene.has requires a key")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.has must be called on a gene")
    let key_val = get_positional_arg(args, 1, has_keyword_args)
    case key_val.kind
    of VkString, VkSymbol:
      return gene_val.gene.props.hasKey(key_val.str.to_key()).to_value()
    else:
      not_allowed("Gene.has key must be a string or symbol")

  gene_class.def_native_method("has", gene_has_method)

  proc gene_get_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let pos_count = get_positional_count(arg_count, has_keyword_args)
    if pos_count < 2:
      not_allowed("Gene.get requires a key")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.get must be called on a gene")
    let key_val = get_positional_arg(args, 1, has_keyword_args)
    var key: Key
    case key_val.kind
    of VkString, VkSymbol:
      key = key_val.str.to_key()
    else:
      not_allowed("Gene.get key must be a string or symbol")
    if gene_val.gene.props.hasKey(key):
      return gene_val.gene.props[key]
    if pos_count >= 3:
      return get_positional_arg(args, 2, has_keyword_args)
    NIL

  gene_class.def_native_method("get", gene_get_method)

  proc gene_set_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 3:
      not_allowed("Gene.set requires key and value")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.set must be called on a gene")
    let key_val = get_positional_arg(args, 1, has_keyword_args)
    var key: Key
    case key_val.kind
    of VkString, VkSymbol:
      key = key_val.str.to_key()
    else:
      not_allowed("Gene.set key must be a string or symbol")
    let value = get_positional_arg(args, 2, has_keyword_args)
    ensure_mutable_gene(gene_val, "set property on")
    gene_val.gene.props[key] = value
    gene_val

  gene_class.def_native_method("set", gene_set_method)

  proc gene_del_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let pos_count = get_positional_count(arg_count, has_keyword_args)
    if pos_count < 2:
      not_allowed("Gene.del requires a key")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.del must be called on a gene")
    ensure_mutable_gene(gene_val, "delete property from")
    var last_removed = NIL
    for i in 1..<pos_count:
      let key_val = get_positional_arg(args, i, has_keyword_args)
      var key: Key
      case key_val.kind
      of VkString, VkSymbol:
        key = key_val.str.to_key()
      else:
        not_allowed("Gene.del key must be a string or symbol")
      if gene_val.gene.props.hasKey(key):
        last_removed = gene_val.gene.props[key]
        gene_val.gene.props.del(key)
    last_removed

  gene_class.def_native_method("del", gene_del_method)

  # Gene child APIs
  proc gene_has_child_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Gene.has_child requires an index")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.has_child must be called on a gene")
    let idx_val = get_positional_arg(args, 1, has_keyword_args)
    if idx_val.kind != VkInt:
      not_allowed("Gene.has_child index must be an integer")
    let idx = idx_val.int64.int
    (idx >= 0 and idx < gene_val.gene.children.len).to_value()

  gene_class.def_native_method("has_child", gene_has_child_method)

  proc gene_get_child_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let pos_count = get_positional_count(arg_count, has_keyword_args)
    if pos_count < 2:
      not_allowed("Gene.get_child requires an index")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.get_child must be called on a gene")
    let idx_val = get_positional_arg(args, 1, has_keyword_args)
    if idx_val.kind != VkInt:
      not_allowed("Gene.get_child index must be an integer")
    let idx = idx_val.int64.int
    if idx >= 0 and idx < gene_val.gene.children.len:
      return gene_val.gene.children[idx]
    if pos_count >= 3:
      return get_positional_arg(args, 2, has_keyword_args)
    NIL

  gene_class.def_native_method("get_child", gene_get_child_method)

  proc gene_set_child_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 3:
      not_allowed("Gene.set_child requires index and value")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.set_child must be called on a gene")
    let idx_val = get_positional_arg(args, 1, has_keyword_args)
    if idx_val.kind != VkInt:
      not_allowed("Gene.set_child index must be an integer")
    let idx = idx_val.int64.int
    if idx < 0 or idx >= gene_val.gene.children.len:
      not_allowed("Gene.set_child index out of bounds")
    let value = get_positional_arg(args, 2, has_keyword_args)
    ensure_mutable_gene(gene_val, "set child on")
    gene_val.gene.children[idx] = value
    gene_val

  gene_class.def_native_method("set_child", gene_set_child_method)

  proc gene_add_child_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Gene.add_child requires a value")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.add_child must be called on a gene")
    let value = get_positional_arg(args, 1, has_keyword_args)
    ensure_mutable_gene(gene_val, "append child to")
    gene_val.gene.children.add(value)
    gene_val

  gene_class.def_native_method("add_child", gene_add_child_method)

  proc gene_ins_child_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 3:
      not_allowed("Gene.ins_child requires index and value")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.ins_child must be called on a gene")
    let idx_val = get_positional_arg(args, 1, has_keyword_args)
    if idx_val.kind != VkInt:
      not_allowed("Gene.ins_child index must be an integer")
    let idx = idx_val.int64.int
    if idx < 0 or idx > gene_val.gene.children.len:
      not_allowed("Gene.ins_child index out of bounds")
    let value = get_positional_arg(args, 2, has_keyword_args)
    ensure_mutable_gene(gene_val, "insert child into")
    gene_val.gene.children.insert(value, idx)
    gene_val

  gene_class.def_native_method("ins_child", gene_ins_child_method)

  proc gene_del_child_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Gene.del_child requires an index")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.del_child must be called on a gene")
    let idx_val = get_positional_arg(args, 1, has_keyword_args)
    if idx_val.kind != VkInt:
      not_allowed("Gene.del_child index must be an integer")
    let idx = idx_val.int64.int
    if idx < 0 or idx >= gene_val.gene.children.len:
      not_allowed("Gene.del_child index out of bounds")
    ensure_mutable_gene(gene_val, "delete child from")
    let removed = gene_val.gene.children[idx]
    gene_val.gene.children.delete(idx)
    removed

  gene_class.def_native_method("del_child", gene_del_child_method)

  proc gene_contains_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Gene.contains requires a value")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.contains must be called on a gene")
    let needle = get_positional_arg(args, 1, has_keyword_args)
    for child in gene_val.gene.children:
      if child == needle:
        return TRUE
    FALSE

  gene_class.def_native_method("contains", gene_contains_method)

  # genetype is alias for type
  gene_class.def_native_method("genetype", gene_type_method)

  proc gene_set_genetype_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Gene.set_genetype requires a type value")
    let gene_val = get_positional_arg(args, 0, has_keyword_args)
    if gene_val.kind != VkGene:
      not_allowed("Gene.set_genetype must be called on a gene")
    let new_type = get_positional_arg(args, 1, has_keyword_args)
    ensure_mutable_gene(gene_val, "set type on")
    gene_val.gene.type = new_type
    gene_val

  gene_class.def_native_method("set_genetype", gene_set_genetype_method)

  let function_class = new_class("Function")
  function_class.parent = object_class

  proc string_seq_value(items: seq[string]): Value {.gcsafe.} =
    var result_ref = new_array_value()
    for item in items:
      array_data(result_ref).add(item.to_value())
    result_ref

  proc callable_param_kind_name(kind: CallableParamKind): string {.gcsafe.} =
    case kind
    of CpkPositional:
      "positional"
    of CpkPositionalRest:
      "positional-rest"
    of CpkKeyword:
      "keyword"
    of CpkKeywordRest:
      "keyword-rest"

  proc type_name_value(type_id: TypeId, type_descs: seq[TypeDesc]): Value {.gcsafe.} =
    let descs =
      if type_descs.len > 0: type_descs
      else: builtin_type_descs()
    let id =
      if type_id == NO_TYPE_ID: BUILTIN_TYPE_ANY_ID
      else: type_id
    type_desc_to_string(id, descs).to_value()

  proc callable_param_metadata(param: CallableParamDesc, type_descs: seq[TypeDesc],
                               name = ""): Value {.gcsafe.} =
    var data = initTable[Key, Value]()
    data["kind".to_key()] = callable_param_kind_name(param.kind).to_value()
    data["name".to_key()] = name.to_value()
    data["keyword".to_key()] = param.keyword_name.to_value()
    data["type".to_key()] = type_name_value(param.type_id, type_descs)
    data["type_id".to_key()] = param.type_id.int.to_value()
    new_map_value(data)

  proc callable_params_metadata(params: seq[CallableParamDesc],
                                type_descs: seq[TypeDesc],
                                param_names: seq[string] = @[]): Value {.gcsafe.} =
    var result_ref = new_array_value()
    for i, param in params:
      let name =
        if i < param_names.len: param_names[i]
        elif param.kind in {CpkKeyword, CpkKeywordRest}: param.keyword_name
        else: ""
      array_data(result_ref).add(callable_param_metadata(param, type_descs, name))
    result_ref

  proc matcher_param_name(param: Matcher): string {.gcsafe.} =
    if param != nil and cast[int64](param.name_key) != 0:
      return get_symbol_gcsafe(symbol_index(param.name_key))
    ""

  proc matcher_param_kind(param: Matcher): CallableParamKind {.gcsafe.} =
    if param.kind == MatchProp or param.is_prop:
      if param.is_splat: CpkKeywordRest else: CpkKeyword
    else:
      if param.is_splat: CpkPositionalRest else: CpkPositional

  proc matcher_param_desc(param: Matcher): CallableParamDesc {.gcsafe.} =
    let kind = matcher_param_kind(param)
    let name = matcher_param_name(param)
    CallableParamDesc(
      kind: kind,
      keyword_name: if kind in {CpkKeyword, CpkKeywordRest}: name else: "",
      type_id: if param.type_id == NO_TYPE_ID: BUILTIN_TYPE_ANY_ID else: param.type_id)

  proc matcher_param_metadata(param: Matcher, type_descs: seq[TypeDesc]): Value {.gcsafe.} =
    callable_param_metadata(matcher_param_desc(param), type_descs, matcher_param_name(param))

  proc matcher_params_metadata(matcher: RootMatcher, start = 0): Value {.gcsafe.} =
    var result_ref = new_array_value()
    if matcher == nil:
      return result_ref
    let descs =
      if matcher.type_descriptors.len > 0: matcher.type_descriptors
      else: builtin_type_descs()
    for i in start..<matcher.children.len:
      array_data(result_ref).add(matcher_param_metadata(matcher.children[i], descs))
    result_ref

  proc native_signature_for_callable(callable: Value): NativeSignature {.gcsafe.} =
    case callable.kind
    of VkNativeFn:
      {.cast(gcsafe).}:
        return lookup_native_signature(callable.ref.native_fn)
    of VkNativeMethod:
      {.cast(gcsafe).}:
        return lookup_native_signature(callable.ref.native_method)
    of VkBoundMethod:
      let meth = callable.ref.bound_method.`method`
      if meth == nil:
        return nil
      if meth.native_signature != nil:
        return meth.native_signature
      if meth.callable.kind == VkNativeFn:
        {.cast(gcsafe).}:
          return lookup_native_signature(meth.callable.ref.native_fn)
    else:
      discard
    nil

  proc matcher_for_callable(callable: Value): tuple[matcher: RootMatcher, start: int,
                                                    receives_self: bool] {.gcsafe.} =
    case callable.kind
    of VkFunction:
      if callable.ref.fn != nil:
        return (callable.ref.fn.matcher, 0, false)
    of VkBlock:
      if callable.ref.`block` != nil:
        return (callable.ref.`block`.matcher, 0, false)
    of VkBoundMethod:
      let meth = callable.ref.bound_method.`method`
      if meth != nil and meth.callable.kind == VkFunction and meth.callable.ref.fn != nil:
        let matcher = meth.callable.ref.fn.matcher
        let start = if matcher != nil and matcher.children.len > 0: 1 else: 0
        return (matcher, start, true)
    of VkMethod:
      let meth = callable.ref.`method`
      if meth != nil and meth.callable.kind == VkFunction and meth.callable.ref.fn != nil:
        let matcher = meth.callable.ref.fn.matcher
        let start = if matcher != nil and matcher.children.len > 0: 1 else: 0
        return (matcher, start, true)
    else:
      discard
    (nil, 0, false)

  proc callable_params_value(callable: Value): Value {.gcsafe.} =
    let sig = native_signature_for_callable(callable)
    if sig != nil:
      return callable_params_metadata(sig.params, sig.type_descriptors, sig.param_names)

    let info = matcher_for_callable(callable)
    matcher_params_metadata(info.matcher, info.start)

  proc callable_return_type_value(callable: Value): Value {.gcsafe.} =
    let sig = native_signature_for_callable(callable)
    if sig != nil:
      return type_name_value(sig.return_type_id, sig.type_descriptors)

    let info = matcher_for_callable(callable)
    if info.matcher == nil:
      return "Any".to_value()
    type_name_value(info.matcher.return_type_id, info.matcher.type_descriptors)

  proc callable_signature_value(callable: Value): Value {.gcsafe.} =
    var data = initTable[Key, Value]()
    let sig = native_signature_for_callable(callable)
    if sig != nil:
      data["params".to_key()] = callable_params_metadata(sig.params,
        sig.type_descriptors, sig.param_names)
      data["return".to_key()] = type_name_value(sig.return_type_id, sig.type_descriptors)
      data["return_type".to_key()] = data["return".to_key()]
      data["return_type_id".to_key()] = sig.return_type_id.int.to_value()
      data["effects".to_key()] = new_array_value()
      data["native?".to_key()] = TRUE
      data["receives_self?".to_key()] = sig.receives_self.to_value()
      data["has_type_annotations?".to_key()] = sig.has_type_annotations.to_value()
      return new_map_value(data)

    let info = matcher_for_callable(callable)
    data["params".to_key()] = matcher_params_metadata(info.matcher, info.start)
    if info.matcher == nil:
      data["return".to_key()] = "Any".to_value()
      data["return_type".to_key()] = "Any".to_value()
      data["return_type_id".to_key()] = BUILTIN_TYPE_ANY_ID.int.to_value()
      data["effects".to_key()] = new_array_value()
      data["has_type_annotations?".to_key()] = FALSE
    else:
      data["return".to_key()] = type_name_value(info.matcher.return_type_id,
        info.matcher.type_descriptors)
      data["return_type".to_key()] = data["return".to_key()]
      data["return_type_id".to_key()] =
        (if info.matcher.return_type_id == NO_TYPE_ID: BUILTIN_TYPE_ANY_ID
         else: info.matcher.return_type_id).int.to_value()
      data["effects".to_key()] = string_seq_value(info.matcher.effects)
      data["has_type_annotations?".to_key()] =
        (info.matcher.has_type_annotations or
         info.matcher.return_type_id notin [NO_TYPE_ID, BUILTIN_TYPE_ANY_ID]).to_value()
    data["native?".to_key()] = FALSE
    data["receives_self?".to_key()] = info.receives_self.to_value()
    new_map_value(data)

  proc require_callable_arg(args: ptr UncheckedArray[Value], arg_count: int,
                            has_keyword_args: bool, method_name: string): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Function." & method_name & " requires self")
    let fn_val = get_positional_arg(args, 0, has_keyword_args)
    if fn_val.kind notin {VkFunction, VkNativeFn, VkNativeMethod, VkBoundMethod, VkBlock, VkMethod}:
      not_allowed("Function." & method_name & " must be called on a callable")
    fn_val

  proc function_intent_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                              arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Function.intent requires self")
    let fn_val = get_positional_arg(args, 0, has_keyword_args)
    if fn_val.kind != VkFunction:
      not_allowed("Function.intent must be called on a function")
    let fn_obj = fn_val.ref.fn
    if fn_obj == nil:
      return NIL
    fn_obj.intent.to_value()

  proc function_examples_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Function.examples requires self")
    let fn_val = get_positional_arg(args, 0, has_keyword_args)
    if fn_val.kind != VkFunction:
      not_allowed("Function.examples must be called on a function")
    let fn_obj = fn_val.ref.fn
    if fn_obj == nil:
      return new_array_value()

    let out_arr = new_array_value()
    for example in fn_obj.examples:
      let arg_arr = new_array_value()
      for arg_expr in example.args:
        array_data(arg_arr).add(arg_expr)
      array_data(out_arr).add(arg_arr)
      case example.expectation_kind
      of FekThrows:
        array_data(out_arr).add("throws".to_symbol_value())
        array_data(out_arr).add(example.expected)
      of FekAnyReturn:
        array_data(out_arr).add("->".to_symbol_value())
        array_data(out_arr).add("_".to_symbol_value())
      of FekReturn:
        array_data(out_arr).add("->".to_symbol_value())
        array_data(out_arr).add(example.expected)
    out_arr

  proc function_call_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                            arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let pos_count = get_positional_count(arg_count, has_keyword_args)
    if pos_count < 1:
      not_allowed("Function.call requires self")
    let fn_val = get_positional_arg(args, 0, has_keyword_args)
    if fn_val.kind notin {VkFunction, VkNativeFn, VkNativeMethod, VkBoundMethod, VkBlock}:
      not_allowed("Function.call must be called on a callable")
    var call_args = newSeq[Value]()
    for i in 1..<pos_count:
      call_args.add(get_positional_arg(args, i, has_keyword_args))
    {.cast(gcsafe).}:
      vm_exec_callable(vm, fn_val, call_args)

  proc function_params_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                              arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    callable_params_value(require_callable_arg(args, arg_count, has_keyword_args, "params"))

  proc function_return_type_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                   arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    callable_return_type_value(require_callable_arg(args, arg_count, has_keyword_args, "return_type"))

  proc function_signature_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                 arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    callable_signature_value(require_callable_arg(args, arg_count, has_keyword_args, "signature"))

  function_class.def_native_method("call", function_call_method)
  function_class.def_native_method("intent", function_intent_method)
  function_class.def_native_method("examples", function_examples_method)
  function_class.def_native_method("params", function_params_method)
  function_class.def_native_method("return_type", function_return_type_method)
  function_class.def_native_method("signature", function_signature_method)

  let function_intent_fn = new_ref(VkNativeFn)
  function_intent_fn.native_fn = function_intent_method
  App.app.gene_ns.ns["function_intent".to_key()] = function_intent_fn.to_ref_value()
  App.app.global_ns.ns["function_intent".to_key()] = function_intent_fn.to_ref_value()

  let function_examples_fn = new_ref(VkNativeFn)
  function_examples_fn.native_fn = function_examples_method
  App.app.gene_ns.ns["function_examples".to_key()] = function_examples_fn.to_ref_value()
  App.app.global_ns.ns["function_examples".to_key()] = function_examples_fn.to_ref_value()

  r = new_ref(VkClass)
  r.class = function_class
  App.app.function_class = r.to_ref_value()
  App.app.gene_ns.ns["Function".to_key()] = App.app.function_class
  App.app.global_ns.ns["Function".to_key()] = App.app.function_class

  let char_class = new_class("Char")
  char_class.parent = object_class
  char_class.def_native_method("to_s", object_to_s_method)
  r = new_ref(VkClass)
  r.class = char_class
  App.app.char_class = r.to_ref_value()
  App.app.gene_ns.ns["Char".to_key()] = App.app.char_class
  App.app.global_ns.ns["Char".to_key()] = App.app.char_class

  let application_class = new_class("Application")
  application_class.parent = object_class

  proc application_package_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                  arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Application.package requires self")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    if self_arg.kind != VkApplication or self_arg.ref.app == nil:
      not_allowed("Application.package must be called on an application")
    let pkg = self_arg.ref.app.pkg
    if pkg == nil:
      return NIL
    let pkg_ref = new_ref(VkPackage)
    pkg_ref.pkg = pkg
    pkg_ref.to_ref_value()

  application_class.def_native_method("package", application_package_method)
  application_class.def_native_method("pkg", application_package_method)
  r = new_ref(VkClass)
  r.class = application_class
  App.app.application_class = r.to_ref_value()
  App.app.gene_ns.ns["Application".to_key()] = App.app.application_class
  App.app.global_ns.ns["Application".to_key()] = App.app.application_class

  proc package_name_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                           arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Package.name requires self")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    if self_arg.kind != VkPackage or self_arg.ref.pkg == nil:
      not_allowed("Package.name must be called on a package")
    self_arg.ref.pkg.name.to_value()

  proc package_version_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                              arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Package.version requires self")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    if self_arg.kind != VkPackage or self_arg.ref.pkg == nil:
      not_allowed("Package.version must be called on a package")
    self_arg.ref.pkg.version

  proc package_dir_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                          arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Package.dir requires self")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    if self_arg.kind != VkPackage or self_arg.ref.pkg == nil:
      not_allowed("Package.dir must be called on a package")
    if self_arg.ref.pkg.dir.len == 0:
      return NIL
    self_arg.ref.pkg.dir.to_value()

  proc package_source_dir_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                 arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Package.source_dir requires self")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    if self_arg.kind != VkPackage or self_arg.ref.pkg == nil:
      not_allowed("Package.source_dir must be called on a package")
    self_arg.ref.pkg.src_path.to_value()

  proc package_main_module_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                  arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Package.main_module requires self")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    if self_arg.kind != VkPackage or self_arg.ref.pkg == nil:
      not_allowed("Package.main_module must be called on a package")
    let main_module = self_arg.ref.pkg.props.getOrDefault("main-module".to_key(), NIL)
    case main_module.kind
    of VkString, VkSymbol:
      main_module.str.to_value()
    else:
      "index".to_value()

  proc package_test_dir_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                               arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Package.test_dir requires self")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    if self_arg.kind != VkPackage or self_arg.ref.pkg == nil:
      not_allowed("Package.test_dir must be called on a package")
    self_arg.ref.pkg.test_path.to_value()

  let package_class = new_class("Package")
  package_class.parent = object_class
  package_class.def_native_method("name", package_name_method)
  package_class.def_native_method("version", package_version_method)
  package_class.def_native_method("dir", package_dir_method)
  package_class.def_native_method("source_dir", package_source_dir_method)
  package_class.def_native_method("main_module", package_main_module_method)
  package_class.def_native_method("test_dir", package_test_dir_method)
  r = new_ref(VkClass)
  r.class = package_class
  App.app.package_class = r.to_ref_value()
  App.app.gene_ns.ns["Package".to_key()] = App.app.package_class
  App.app.global_ns.ns["Package".to_key()] = App.app.package_class

  let namespace_class = new_class("Namespace")
  namespace_class.parent = object_class
  r = new_ref(VkClass)
  r.class = namespace_class
  App.app.namespace_class = r.to_ref_value()
  App.app.gene_ns.ns["Namespace".to_key()] = App.app.namespace_class
  App.app.global_ns.ns["Namespace".to_key()] = App.app.namespace_class

  # Namespace member APIs
  proc ns_has_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Namespace.has requires a key")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.has must be called on a namespace")
    let key_val = get_positional_arg(args, 1, has_keyword_args)
    case key_val.kind
    of VkString, VkSymbol:
      return ns_val.ref.ns.members.hasKey(key_val.str.to_key()).to_value()
    else:
      not_allowed("Namespace.has key must be a string or symbol")

  namespace_class.def_native_method("has", ns_has_method)

  proc ns_get_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let pos_count = get_positional_count(arg_count, has_keyword_args)
    if pos_count < 2:
      not_allowed("Namespace.get requires a key")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.get must be called on a namespace")
    let key_val = get_positional_arg(args, 1, has_keyword_args)
    var key: Key
    case key_val.kind
    of VkString, VkSymbol:
      key = key_val.str.to_key()
    else:
      not_allowed("Namespace.get key must be a string or symbol")
    if ns_val.ref.ns.members.hasKey(key):
      return ns_val.ref.ns.members[key]
    if pos_count >= 3:
      return get_positional_arg(args, 2, has_keyword_args)
    NIL

  namespace_class.def_native_method("get", ns_get_method)

  proc ns_set_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 3:
      not_allowed("Namespace.set requires key and value")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.set must be called on a namespace")
    let key_val = get_positional_arg(args, 1, has_keyword_args)
    var key: Key
    case key_val.kind
    of VkString, VkSymbol:
      key = key_val.str.to_key()
    else:
      not_allowed("Namespace.set key must be a string or symbol")
    let value = get_positional_arg(args, 2, has_keyword_args)
    ns_val.ref.ns.members[key] = value
    ns_val

  namespace_class.def_native_method("set", ns_set_method)

  proc ns_del_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let pos_count = get_positional_count(arg_count, has_keyword_args)
    if pos_count < 2:
      not_allowed("Namespace.del requires a key")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.del must be called on a namespace")
    var last_removed = NIL
    for i in 1..<pos_count:
      let key_val = get_positional_arg(args, i, has_keyword_args)
      var key: Key
      case key_val.kind
      of VkString, VkSymbol:
        key = key_val.str.to_key()
      else:
        not_allowed("Namespace.del key must be a string or symbol")
      if ns_val.ref.ns.members.hasKey(key):
        last_removed = ns_val.ref.ns.members[key]
        ns_val.ref.ns.members.del(key)
    last_removed

  namespace_class.def_native_method("del", ns_del_method)

  proc ns_empty_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Namespace.empty requires self")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.empty must be called on a namespace")
    (ns_val.ref.ns.members.len == 0).to_value()

  namespace_class.def_native_method("empty", ns_empty_method)
  namespace_class.def_native_method("empty?", ns_empty_method)

  proc ns_not_empty_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Namespace.not_empty? requires self")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.not_empty? must be called on a namespace")
    (ns_val.ref.ns.members.len != 0).to_value()

  namespace_class.def_native_method("not_empty?", ns_not_empty_method)

  proc ns_clear_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Namespace.clear requires self")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.clear must be called on a namespace")
    ns_val.ref.ns.members.clear()
    ns_val

  namespace_class.def_native_method("clear", ns_clear_method)

  proc ns_size_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Namespace.size requires self")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.size must be called on a namespace")
    ns_val.ref.ns.members.len.to_value()

  namespace_class.def_native_method("size", ns_size_method)

  proc ns_keys_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Namespace.keys requires self")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.keys must be called on a namespace")
    var result_ref = new_array_value()
    for key, _ in ns_val.ref.ns.members:
      let key_val = cast[Value](key)
      array_data(result_ref).add(key_val.str.to_value())
    result_ref

  namespace_class.def_native_method("keys", ns_keys_method)

  proc ns_values_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Namespace.values requires self")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.values must be called on a namespace")
    var result_ref = new_array_value()
    for _, value in ns_val.ref.ns.members:
      array_data(result_ref).add(value)
    result_ref

  namespace_class.def_native_method("values", ns_values_method)

  proc ns_pairs_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Namespace.pairs requires self")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.pairs must be called on a namespace")
    var result_ref = new_array_value()
    for key, value in ns_val.ref.ns.members:
      var pair = new_array_value()
      let key_val = cast[Value](key)
      array_data(pair).add(key_val.str.to_value())
      array_data(pair).add(value)
      array_data(result_ref).add(pair)
    result_ref

  namespace_class.def_native_method("pairs", ns_pairs_method)

  proc ns_each_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Namespace.each requires a function")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.each must be called on a namespace")
    let callback = get_positional_arg(args, 1, has_keyword_args)
    case callback.kind
    of VkFunction, VkNativeFn, VkNativeMethod, VkBoundMethod, VkBlock:
      for key, value in ns_val.ref.ns.members:
        let key_val = cast[Value](key)
        {.cast(gcsafe).}:
          discard vm_exec_callable(vm, callback, @[key_val.str.to_value(), value])
    else:
      not_allowed("each callback must be callable, got " & $callback.kind)
    ns_val

  namespace_class.def_native_method("each", ns_each_method)

  proc ns_map_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Namespace.map requires a function")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.map must be called on a namespace")
    let callback = get_positional_arg(args, 1, has_keyword_args)
    var result_ref = new_map_value()
    case callback.kind
    of VkFunction, VkNativeFn, VkNativeMethod, VkBoundMethod, VkBlock:
      for key, value in ns_val.ref.ns.members:
        let key_val = cast[Value](key).str.to_value()
        var mapped: Value
        {.cast(gcsafe).}:
          mapped = vm_exec_callable(vm, callback, @[key_val, value])
        map_data(result_ref)[key] = mapped
    else:
      not_allowed("map callback must be callable, got " & $callback.kind)
    result_ref

  namespace_class.def_native_method("map", ns_map_method)

  proc ns_reduce_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 3:
      not_allowed("Namespace.reduce requires an initial value and a reducer function")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.reduce must be called on a namespace")
    var accumulator = get_positional_arg(args, 1, has_keyword_args)
    let reducer = get_positional_arg(args, 2, has_keyword_args)
    case reducer.kind
    of VkFunction, VkNativeFn, VkNativeMethod, VkBoundMethod, VkBlock:
      for key, value in ns_val.ref.ns.members:
        let key_val = cast[Value](key).str.to_value()
        {.cast(gcsafe).}:
          accumulator = vm_exec_callable(vm, reducer, @[accumulator, key_val, value])
    else:
      not_allowed("reduce reducer must be callable, got " & $reducer.kind)
    accumulator

  namespace_class.def_native_method("reduce", ns_reduce_method)

  proc ns_on_member_missing_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("on_member_missing requires a handler function")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("on_member_missing must be called on a namespace")
    let handler = get_positional_arg(args, 1, has_keyword_args)
    case handler.kind
    of VkFunction, VkNativeFn, VkNativeMethod, VkBoundMethod, VkBlock:
      ns_val.ref.ns.on_member_missing.add(handler)
    else:
      not_allowed("on_member_missing handler must be callable, got " & $handler.kind)
    ns_val

  namespace_class.def_native_method("on_member_missing", ns_on_member_missing_method)

  proc ns_name_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Namespace.name requires self")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.name must be called on a namespace")
    ns_val.ref.ns.name.to_value()

  namespace_class.def_native_method("name", ns_name_method)
  namespace_class.def_native_method("to_s", proc(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 1:
      not_allowed("Namespace.to_s requires self")
    let ns_val = get_positional_arg(args, 0, has_keyword_args)
    if ns_val.kind != VkNamespace:
      not_allowed("Namespace.to_s must be called on a namespace")
    let name = ns_val.ref.ns.name
    (if name.len > 0: name else: "<root>").to_value()
  )
