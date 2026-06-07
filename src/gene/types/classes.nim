import strutils, tables

import ./type_defs
import ./core

#################### Class #######################

proc new_class*(name: string, parent: Class): Class =
  result = Class(
    name: name,
    ns: new_namespace(nil, name),
    parent: parent,
    constructor: NIL,
    members: initTable[Key, Value](),
    methods: initTable[Key, Method](),
    implementations: initTable[GeneInterface, Implementation](),
    version: 0,
  )

proc new_class*(name: string): Class =
  var parent: Class
  # if VM.object_class != nil:
  #   parent = VM.object_class.class
  new_class(name, parent)

proc get_constructor*(self: Class): Value =
  if self.constructor.is_nil:
    if not self.parent.is_nil:
      return self.parent.get_constructor()
  else:
    return self.constructor

proc has_method*(self: Class, name: Key): bool {.inline.} =
  if self.methods.has_key(name):
    return true
  elif self.parent != nil:
    return self.parent.has_method(name)

proc has_method*(self: Class, name: string): bool {.inline.} =
  self.has_method(name.to_key)

proc get_method*(self: Class, name: Key): Method {.inline.} =
  let found = self.methods.get_or_default(name, nil)
  if not found.is_nil:
    return found
  elif self.parent != nil:
    return self.parent.get_method(name)
  # else:
  #   not_allowed("No method available: " & name.to_s)

proc get_method*(self: Class, name: string): Method {.inline.} =
  self.get_method(name.to_key)

proc get_super_method*(self: Class, name: string): Method {.inline.} =
  if self.parent != nil:
    return self.parent.get_method(name)
  else:
    not_allowed("No super method available: " & name)

proc get_class*(val: Value): Class {.inline.} =
  case val.kind:
    of VkApplication:
      return App.ref.app.application_class.ref.class
    of VkPackage:
      return App.ref.app.package_class.ref.class
    of VkInstance:
      return val.instance_class
    of VkCustom:
      if val.ref.custom_class != nil:
        return val.ref.custom_class
      else:
        return App.ref.app.object_class.ref.class
    # of VkCast:
    #   return val.cast_class
    of VkClass:
      return App.ref.app.class_class.ref.class
    of VkNamespace:
      return App.ref.app.namespace_class.ref.class
    of VkInterface:
      if App.ref.app.interface_class.kind == VkClass:
        return App.ref.app.interface_class.ref.class
      else:
        return App.ref.app.object_class.ref.class
    of VkAdapter:
      if App.ref.app.adapter_class.kind == VkClass:
        return App.ref.app.adapter_class.ref.class
      else:
        return App.ref.app.object_class.ref.class
    of VkAdapterInternal:
      # AdapterInternal delegates to Map class for method access
      if App.ref.app.map_class.kind == VkClass:
        return App.ref.app.map_class.ref.class
      else:
        return App.ref.app.object_class.ref.class
    of VkFuture:
      if App.ref.app.future_class.kind == VkClass:
        return App.ref.app.future_class.ref.class
      else:
        return nil
    of VkGenerator:
      if App.ref.app.generator_class.kind == VkClass:
        return App.ref.app.generator_class.ref.class
      else:
        return nil
    of VkInterceptor:
      if App.ref.app.interceptor_class.kind == VkClass:
        return App.ref.app.interceptor_class.ref.class
      else:
        return nil
    of VkInterception:
      if App.ref.app.interception_class.kind == VkClass:
        return App.ref.app.interception_class.ref.class
      else:
        return nil
    # of VkThread:
    #   return App.ref.app.thread_class.ref.class
    # of VkThreadMessage:
    #   return App.ref.app.thread_message_class.ref.class
    # of VkNativeFile:
    #   return App.ref.app.file_class.ref.class
    # of VkException:
    #   let ex = val.exception
    #   if ex is ref Exception:
    #     let ex = cast[ref Exception](ex)
    #     if ex.instance != nil:
    #       return ex.instance.instance_class
    #     else:
    #       return App.ref.app.exception_class.ref.class
    #   else:
    #     return App.ref.app.exception_class.ref.class
    of VkNil:
      return App.ref.app.nil_class.ref.class
    of VkBool:
      return App.ref.app.bool_class.ref.class
    of VkInt:
      return App.ref.app.int_class.ref.class
    of VkFloat:
      return App.ref.app.float_class.ref.class
    of VkChar:
      return App.ref.app.char_class.ref.class
    of VkString:
      return App.ref.app.string_class.ref.class
    of VkSymbol:
      return App.ref.app.symbol_class.ref.class
    of VkComplexSymbol:
      return App.ref.app.complex_symbol_class.ref.class
    of VkArray:
      return App.ref.app.array_class.ref.class
    of VkMap:
      return App.ref.app.map_class.ref.class
    of VkHashMap:
      return App.ref.app.hash_map_class.ref.class
    of VkSet:
      return App.ref.app.hash_set_class.ref.class
    of VkGene:
      return App.ref.app.gene_class.ref.class
    of VkRegex:
      return App.ref.app.regex_class.ref.class
    of VkRange:
      return App.ref.app.range_class.ref.class
    # of VkDate:
    #   return App.ref.app.date_class.ref.class
    # of VkDateTime:
    #   return App.ref.app.datetime_class.ref.class
    # of VkTime:
    #   return App.ref.app.time_class.ref.class
    of VkFunction:
      return App.ref.app.function_class.ref.class
    # of VkTimezone:
    #   return App.ref.app.timezone_class.ref.class
    # of VkAny:
    #   if val.any_class == nil:
    #     return App.ref.app.object_class.ref.class
    #   else:
    #     return val.any_class
    # of VkCustom:
    #   if val.custom_class == nil:
    #     return App.ref.app.object_class.ref.class
    #   else:
    #     return val.custom_class
    else:
      todo("get_class " & $val.kind)

proc has_object_class*(val: Value): bool {.inline.} =
  case val.kind
  of VkInstance, VkCustom:
    true
  else:
    false

proc get_object_class*(val: Value): Class {.inline.} =
  case val.kind
  of VkInstance:
    val.instance_class
  of VkCustom:
    val.ref.custom_class
  else:
    nil

proc require_object_class*(val: Value, context: string): Class {.inline.} =
  let cls = val.get_object_class()
  if cls.is_nil:
    raise new_exception(type_defs.Exception, context)
  cls

proc object_class_name*(val: Value): string {.inline.} =
  let cls = val.get_object_class()
  if cls.is_nil or cls.name.len == 0:
    return "UnknownObject"
  cls.name

proc is_a*(self: Value, class: Class): bool {.inline.} =
  var my_class = self.get_class
  while true:
    if my_class == class:
      return true
    if my_class.parent == nil:
      return false
    else:
      my_class = my_class.parent

proc native_type_id_for_class_value(class_value: Value, type_descs: var seq[TypeDesc]): TypeId =
  if class_value == NIL or class_value.kind != VkClass:
    return BUILTIN_TYPE_ANY_ID
  let cls = class_value.ref.class
  if cls.is_nil or cls.name.len == 0:
    return BUILTIN_TYPE_ANY_ID
  let builtin_id = lookup_builtin_type(cls.name)
  if builtin_id != NO_TYPE_ID:
    return builtin_id
  let module_path =
    if cls.module_path.len > 0: cls.module_path
    else: BUILTIN_TYPE_MODULE_PATH
  intern_type_desc(type_descs, TypeDesc(module_path: module_path,
    kind: TdkNamed, name: cls.name))

proc native_call_arg_type(type_id: TypeId, type_descs: seq[TypeDesc]): CallArgType =
  if type_id == BUILTIN_TYPE_INT_ID:
    return CatInt64
  if type_id == BUILTIN_TYPE_FLOAT_ID:
    return CatFloat64
  if type_id >= 0 and type_id.int < type_descs.len:
    let desc = type_descs[type_id.int]
    if desc.kind == TdkNamed:
      case desc.name
      of "Int": return CatInt64
      of "Float": return CatFloat64
      else: discard
  CatValue

proc native_call_return_type(type_id: TypeId, type_descs: seq[TypeDesc]): CallReturnType =
  if type_id == BUILTIN_TYPE_INT_ID:
    return CrtInt64
  if type_id == BUILTIN_TYPE_FLOAT_ID:
    return CrtFloat64
  if type_id >= 0 and type_id.int < type_descs.len:
    let desc = type_descs[type_id.int]
    if desc.kind == TdkNamed:
      case desc.name
      of "Int": return CrtInt64
      of "Float": return CrtFloat64
      else: discard
  CrtValue

proc split_signature_items(input: string): seq[string] =
  var current = ""
  var depth = 0
  for ch in input:
    case ch
    of '(':
      depth.inc()
      current.add(ch)
    of ')':
      depth.dec()
      current.add(ch)
    of ' ', '\t', '\n', '\r':
      if depth == 0:
        if current.len > 0:
          result.add(current)
          current = ""
      else:
        current.add(ch)
    else:
      current.add(ch)
  if current.len > 0:
    result.add(current)

proc parse_builtin_native_type(type_expr: string, type_descs: var seq[TypeDesc]): TypeId =
  let expr = type_expr.strip()
  if expr.len == 0:
    return BUILTIN_TYPE_ANY_ID
  let builtin_id = lookup_builtin_type(expr)
  if builtin_id != NO_TYPE_ID:
    return builtin_id
  if "|" in expr:
    let union_expr =
      if expr.startsWith("(") and expr.endsWith(")"): expr[1..^2].strip()
      else: expr
    var members: seq[TypeId] = @[]
    for part in union_expr.split("|"):
      members.add(parse_builtin_native_type(part, type_descs))
    return intern_type_desc(type_descs, TypeDesc(module_path: BUILTIN_TYPE_MODULE_PATH,
      kind: TdkUnion, members: members))
  if expr.startsWith("(") and expr.endsWith(")"):
    let inner = expr[1..^2].strip()
    let parts = split_signature_items(inner)
    if parts.len == 0:
      not_allowed("native_sig has empty applied type")
    let ctor_id = lookup_builtin_type(parts[0])
    if ctor_id == NO_TYPE_ID:
      not_allowed("native_sig only accepts built-in types, got " & parts[0])
    var args: seq[TypeId] = @[]
    for i in 1..<parts.len:
      args.add(parse_builtin_native_type(parts[i], type_descs))
    return intern_type_desc(type_descs, TypeDesc(module_path: BUILTIN_TYPE_MODULE_PATH,
      kind: TdkApplied, ctor: parts[0], args: args))
  not_allowed("native_sig only accepts built-in types, got " & expr)
  BUILTIN_TYPE_ANY_ID

proc native_signature_with_receiver(sig: NativeSignature, receives_self: bool): NativeSignature =
  if sig == nil:
    return nil
  var abi_args: seq[CallArgType] = @[]
  if receives_self:
    abi_args.add(CatValue)
  abi_args.add(sig.abi_arg_types)
  NativeSignature(
    params: sig.params,
    param_names: sig.param_names,
    return_type_id: sig.return_type_id,
    type_descriptors: sig.type_descriptors,
    module_path: sig.module_path,
    receives_self: receives_self,
    has_type_annotations: sig.has_type_annotations,
    is_variadic: sig.is_variadic,
    arity_min: sig.arity_min,
    arity_max: sig.arity_max,
    abi_arg_types: abi_args,
    abi_return_type: sig.abi_return_type)

proc native_param_name_from_matcher(matcher: Matcher): string =
  try:
    if cast[int64](matcher.name_key) != 0:
      return cast[Value](matcher.name_key).str
  except CatchableError:
    discard
  ""

proc native_param_kind_from_matcher(matcher: Matcher): CallableParamKind =
  if matcher.kind == MatchProp or matcher.is_prop:
    if matcher.is_splat: CpkKeywordRest else: CpkKeyword
  else:
    if matcher.is_splat: CpkPositionalRest else: CpkPositional

proc build_native_signature_from_matcher*(matcher: RootMatcher,
                                          receives_self = false): NativeSignature =
  if matcher == nil:
    return nil

  var params: seq[CallableParamDesc] = @[]
  var param_names: seq[string] = @[]
  var abi_args: seq[CallArgType] = @[]
  var has_annotations = false
  var is_variadic = false
  var arity_min = 0
  var arity_max = 0

  if receives_self:
    abi_args.add(CatValue)

  let type_descs =
    if matcher.type_descriptors.len > 0: matcher.type_descriptors
    else: builtin_type_descs()

  for child in matcher.children:
    let param_kind = native_param_kind_from_matcher(child)
    let param_name = native_param_name_from_matcher(child)
    let type_id =
      if child.type_id == NO_TYPE_ID: BUILTIN_TYPE_ANY_ID
      else: child.type_id
    let keyword_name =
      if param_kind in {CpkKeyword, CpkKeywordRest}: param_name
      else: ""

    params.add(CallableParamDesc(kind: param_kind,
      keyword_name: keyword_name, type_id: type_id))
    param_names.add(param_name)
    abi_args.add(native_call_arg_type(type_id, type_descs))

    if type_id != BUILTIN_TYPE_ANY_ID and type_id != NO_TYPE_ID:
      has_annotations = true
    if param_kind in {CpkPositionalRest, CpkKeywordRest}:
      is_variadic = true
    if param_kind == CpkPositional:
      if child.required:
        arity_min.inc()
      arity_max.inc()
    elif param_kind == CpkPositionalRest:
      arity_max = -1

  let return_type_id =
    if matcher.return_type_id == NO_TYPE_ID: BUILTIN_TYPE_ANY_ID
    else: matcher.return_type_id
  if return_type_id != BUILTIN_TYPE_ANY_ID and return_type_id != NO_TYPE_ID:
    has_annotations = true

  NativeSignature(
    params: params,
    param_names: param_names,
    return_type_id: return_type_id,
    type_descriptors: type_descs,
    module_path: BUILTIN_TYPE_MODULE_PATH,
    receives_self: receives_self,
    has_type_annotations: has_annotations,
    is_variadic: is_variadic,
    arity_min: arity_min,
    arity_max: arity_max,
    abi_arg_types: abi_args,
    abi_return_type: native_call_return_type(return_type_id, type_descs))

proc build_native_signature_from_gene*(params_value: Value,
                                       return_type_value: Value,
                                       cu_type_descs: var seq[TypeDesc],
                                       type_aliases: Table[string, TypeId],
                                       module_path: string,
                                       type_registry: ModuleTypeRegistry = nil,
                                       receives_self = false): NativeSignature =
  if params_value.kind != VkArray:
    not_allowed("native signature parameters must be an array")

  var fn_value = new_gene_value()
  fn_value.gene.type = "fn".to_symbol_value()
  fn_value.gene.children.add("__native_signature".to_symbol_value())
  fn_value.gene.children.add(params_value)
  if return_type_value != NIL:
    fn_value.gene.children.add("->".to_symbol_value())
    fn_value.gene.children.add(return_type_value)
  fn_value.gene.children.add(NIL)

  let fn = to_function(fn_value, cu_type_descs, type_aliases,
    module_path, type_registry)
  result = build_native_signature_from_matcher(fn.matcher, receives_self)
  if result != nil:
    result.module_path = module_path

proc native_signature_param_key(sig: NativeSignature, param: CallableParamDesc): string =
  let descs =
    if sig.type_descriptors.len > 0: sig.type_descriptors
    else: builtin_type_descs()
  let type_key = type_desc_key_for_id(descs, param.type_id)
  case param.kind
  of CpkPositional:
    "pos:" & type_key
  of CpkPositionalRest:
    "rest:" & type_key
  of CpkKeyword:
    "kw:" & param.keyword_name & ":" & type_key
  of CpkKeywordRest:
    "kwrest:" & type_key

proc native_signature_key(sig: NativeSignature): string =
  if sig == nil:
    return "nil"
  let descs =
    if sig.type_descriptors.len > 0: sig.type_descriptors
    else: builtin_type_descs()
  var params: seq[string] = @[]
  for param in sig.params:
    params.add(native_signature_param_key(sig, param))
  "arity:" & $sig.arity_min & ".." & $sig.arity_max &
    ";params:[" & params.join(",") & "]" &
    ";return:" & type_desc_key_for_id(descs, sig.return_type_id)

proc native_signatures_match(existing, incoming: NativeSignature): bool =
  if existing == nil or incoming == nil:
    return existing == incoming
  native_signature_key(existing) == native_signature_key(incoming)

proc native_signature_type_contains_var(sig: NativeSignature, type_id: TypeId,
                                        depth = 0): bool =
  if sig == nil or type_id == NO_TYPE_ID or depth > 64:
    return false
  let descs =
    if sig.type_descriptors.len > 0: sig.type_descriptors
    else: builtin_type_descs()
  if type_id < 0 or type_id.int >= descs.len:
    return false
  let desc = descs[type_id.int]
  case desc.kind
  of TdkVar:
    true
  of TdkApplied:
    for arg in desc.args:
      if native_signature_type_contains_var(sig, arg, depth + 1):
        return true
    false
  of TdkUnion:
    for member in desc.members:
      if native_signature_type_contains_var(sig, member, depth + 1):
        return true
    false
  of TdkFn:
    for param in desc.params:
      if native_signature_type_contains_var(sig, param.type_id, depth + 1):
        return true
    native_signature_type_contains_var(sig, desc.ret, depth + 1)
  else:
    false

proc native_signature_contains_type_vars(sig: NativeSignature): bool =
  if sig == nil:
    return false
  for param in sig.params:
    if native_signature_type_contains_var(sig, param.type_id):
      return true
  native_signature_type_contains_var(sig, sig.return_type_id)

proc ensure_native_signature_supported(sig: NativeSignature, context: string) =
  if native_signature_contains_type_vars(sig):
    not_allowed(context & " does not support generic native signatures yet; use concrete types or Any")

proc ensure_native_signature_assignment(existing, incoming: NativeSignature,
                                        context: string,
                                        allow_override: bool) =
  ensure_native_signature_supported(incoming, context)
  if allow_override or existing == nil or not existing.has_type_annotations:
    return
  if native_signatures_match(existing, incoming):
    return
  let override_context =
    if context.endsWith("!"): context
    else: context & "!"
  not_allowed(context & " conflicts with existing native signature; use " &
    override_context & " to override")

proc attach_native_function_signature*(target: Value, sig: NativeSignature,
                                       context = "$assign-type",
                                       allow_override = false): NativeSignature =
  if target.kind != VkNativeFn:
    not_allowed(context & " target must be a native function, got " & $target.kind)
  let existing = lookup_native_signature(target.ref.native_fn)
  ensure_native_signature_assignment(existing, sig, context, allow_override)
  register_native_signature(target.ref.native_fn, sig)
  sig

proc attach_native_method_signature*(class: Class, name: string,
                                     sig: NativeSignature,
                                     context = "$assign-method-type",
                                     allow_override = false): NativeSignature =
  if class == nil:
    not_allowed(context & " target must be a class")
  let meth = class.get_method(name)
  if meth == nil:
    not_allowed("No native method " & class.name & "." & name)
  if meth.callable.kind != VkNativeFn:
    not_allowed(class.name & "." & name & " is not a native method")
  let method_sig = native_signature_with_receiver(sig, receives_self = true)
  let existing =
    if meth.native_signature != nil: meth.native_signature
    else: lookup_native_signature(meth.callable.ref.native_fn)
  ensure_native_signature_assignment(existing, method_sig, context, allow_override)
  register_native_signature(meth.callable.ref.native_fn, method_sig)
  meth.native_signature_known = method_sig != nil
  meth.native_signature = method_sig
  if meth.class != nil:
    meth.class.version.inc()
  method_sig

proc attach_native_constructor_signature*(class: Class,
                                          sig: NativeSignature,
                                          context = "$assign-ctor-type",
                                          allow_override = false): NativeSignature =
  if class == nil:
    not_allowed(context & " target must be a class")
  let ctor = class.get_constructor()
  if ctor == NIL:
    not_allowed("Class " & class.name & " has no constructor")
  if ctor.kind != VkNativeFn:
    not_allowed("Class " & class.name & " constructor is not native")
  let existing =
    if class.constructor_native_signature != nil: class.constructor_native_signature
    else: lookup_native_signature(ctor.ref.native_fn)
  ensure_native_signature_assignment(existing, sig, context, allow_override)
  register_native_signature(ctor.ref.native_fn, sig)
  class.constructor_native_signature_known = sig != nil
  class.constructor_native_signature = sig
  class.version.inc()
  sig

proc native_sig*(signature: string): NativeSignature =
  let arrow = signature.find("->")
  let params_part =
    if arrow >= 0: signature[0..<arrow].strip()
    else: signature.strip()
  let return_part =
    if arrow >= 0: signature[(arrow + 2)..^1].strip()
    else: "Any"
  if not params_part.startsWith("[") or not params_part.endsWith("]"):
    not_allowed("native_sig expects [params] -> Return")

  var type_descs = builtin_type_descs()
  var params: seq[CallableParamDesc] = @[]
  var param_names: seq[string] = @[]
  var abi_args: seq[CallArgType] = @[]
  var has_annotations = false

  let tokens = split_signature_items(params_part[1..^2].strip())
  var i = 0
  while i < tokens.len:
    var name = "argument " & $(params.len + 1)
    var type_token = ""
    let token = tokens[i]
    if token.endsWith(":"):
      name = token[0..^2]
      i.inc()
      if i >= tokens.len:
        not_allowed("native_sig parameter '" & name & "' is missing a type")
      type_token = tokens[i]
    elif token.contains(":"):
      let parts = token.split(":", maxsplit = 1)
      name = parts[0]
      if parts.len > 1 and parts[1].len > 0:
        type_token = parts[1]
      else:
        i.inc()
        if i >= tokens.len:
          not_allowed("native_sig parameter '" & name & "' is missing a type")
        type_token = tokens[i]
    else:
      type_token = token

    let type_id = parse_builtin_native_type(type_token, type_descs)
    params.add(CallableParamDesc(kind: CpkPositional,
      keyword_name: "", type_id: type_id))
    param_names.add(name)
    abi_args.add(native_call_arg_type(type_id, type_descs))
    if type_id != BUILTIN_TYPE_ANY_ID and type_id != NO_TYPE_ID:
      has_annotations = true
    i.inc()

  let return_type_id = parse_builtin_native_type(return_part, type_descs)
  if return_type_id != BUILTIN_TYPE_ANY_ID and return_type_id != NO_TYPE_ID:
    has_annotations = true

  NativeSignature(
    params: params,
    param_names: param_names,
    return_type_id: return_type_id,
    type_descriptors: type_descs,
    module_path: BUILTIN_TYPE_MODULE_PATH,
    receives_self: false,
    has_type_annotations: has_annotations,
    is_variadic: false,
    arity_min: params.len,
    arity_max: params.len,
    abi_arg_types: abi_args,
    abi_return_type: native_call_return_type(return_type_id, type_descs))

proc build_native_signature_from_legacy*(params: openArray[(string, Value)],
                                         returns: Value = NIL,
                                         receives_self = true,
                                         module_path = BUILTIN_TYPE_MODULE_PATH): NativeSignature =
  var type_descs = builtin_type_descs()
  var param_descs: seq[CallableParamDesc] = @[]
  var param_names: seq[string] = @[]
  var has_annotations = false
  var abi_args: seq[CallArgType] = @[]

  if receives_self:
    abi_args.add(CatValue)

  for p in params:
    let type_id = native_type_id_for_class_value(p[1], type_descs)
    param_descs.add(CallableParamDesc(kind: CpkPositional,
      keyword_name: "", type_id: type_id))
    param_names.add(p[0])
    abi_args.add(native_call_arg_type(type_id, type_descs))
    if type_id != BUILTIN_TYPE_ANY_ID and type_id != NO_TYPE_ID:
      has_annotations = true

  let return_type_id = native_type_id_for_class_value(returns, type_descs)
  if return_type_id != BUILTIN_TYPE_ANY_ID and return_type_id != NO_TYPE_ID:
    has_annotations = true

  NativeSignature(
    params: param_descs,
    param_names: param_names,
    return_type_id: return_type_id,
    type_descriptors: type_descs,
    module_path: module_path,
    receives_self: receives_self,
    has_type_annotations: has_annotations,
    is_variadic: false,
    arity_min: param_descs.len,
    arity_max: param_descs.len,
    abi_arg_types: abi_args,
    abi_return_type: native_call_return_type(return_type_id, type_descs))

proc def_native_method*(self: Class, name: string, f: NativeFn,
                        params: openArray[(string, Value)],
                        returns: Value = NIL) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  let sig = build_native_signature_from_legacy(params, returns,
    receives_self = true, module_path = self.module_path)
  register_native_signature(f, sig)
  self.methods[name.to_key()] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
    native_signature_known: true,
    native_signature: sig,
  )
  self.version.inc()

proc def_native_method*(self: Class, name: string, f: NativeFn,
                        sig: NativeSignature) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  let method_sig = native_signature_with_receiver(sig, receives_self = true)
  register_native_signature(f, method_sig)
  self.methods[name.to_key()] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
    native_signature_known: method_sig != nil,
    native_signature: method_sig,
  )
  self.version.inc()

proc def_native_method*(self: Class, name: string, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.methods[name.to_key()] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
    native_signature_known: false,
    native_signature: nil,
  )
  self.version.inc()

proc def_member*(self: Class, name: string, value: Value) =
  self.members[name.to_key()] = value
  self.version.inc()

proc def_static_method*(self: Class, name: string, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.members[name.to_key()] = r.to_ref_value()
  self.version.inc()

proc get_member*(self: Class, name: Key): Value =
  if self.members.hasKey(name):
    return self.members[name]
  if not self.parent.is_nil:
    return self.parent.get_member(name)
  return NIL

proc def_native_constructor*(self: Class, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.constructor = r.to_ref_value()
  self.constructor_native_signature_known = false
  self.constructor_native_signature = nil

proc def_native_constructor*(self: Class, f: NativeFn, sig: NativeSignature) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  let ctor_sig = native_signature_with_receiver(sig, receives_self = false)
  register_native_signature(f, ctor_sig)
  self.constructor = r.to_ref_value()
  self.constructor_native_signature_known = ctor_sig != nil
  self.constructor_native_signature = ctor_sig

proc def_native_macro_method*(self: Class, name: string, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  exempt_native_signature_strict_check(f)
  self.methods[name.to_key()] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
    is_macro: true,
    native_signature_known: false,
    native_signature: nil,
  )
  self.version.inc()

proc add_standard_instance_methods*(class: Class) =
  # Currently no standard methods to add
  discard

#################### Method ######################

proc new_method*(class: Class, name: string, fn: Function): Method =
  let r = new_ref(VkFunction)
  r.fn = fn
  return Method(
    class: class,
    name: name,
    callable: r.to_ref_value(),
    native_signature_known: false,
    native_signature: nil,
  )

proc clone*(self: Method): Method =
  return Method(
    class: self.class,
    name: self.name,
    callable: self.callable,
    is_macro: self.is_macro,
    native_signature_known: self.native_signature_known,
    native_signature: self.native_signature,
  )

#################### Callable ######################

proc new_callable*(kind: CallableKind, name: string = ""): Callable =
  result = Callable(kind: kind, name: name, arity: 0, flags: {})

  # Set default flags based on kind
  case kind:
  of CkFunction:
    result.flags = {CfEvaluateArgs}
  of CkNativeFunction:
    result.flags = {CfEvaluateArgs, CfIsNative}
  of CkMethod:
    result.flags = {CfEvaluateArgs, CfIsMethod, CfNeedsSelf}
  of CkNativeMethod:
    result.flags = {CfEvaluateArgs, CfIsMethod, CfNeedsSelf, CfIsNative}
  of CkBlock:
    result.flags = {CfEvaluateArgs}

proc get_arity*(matcher: RootMatcher): int =
  # Calculate minimum required arguments
  result = 0
  for child in matcher.children:
    if child.required:
      result.inc()

proc to_callable*(fn: Function): Callable =
  result = new_callable(CkFunction, fn.name)
  result.fn = fn
  result.arity = fn.matcher.get_arity()

proc to_callable*(native_fn: NativeFn, name: string = "", arity: int = 0): Callable =
  result = new_callable(CkNativeFunction, name)
  result.native_fn = native_fn
  result.arity = arity

proc to_callable*(blk: Block): Callable =
  result = new_callable(CkBlock)
  result.block_fn = blk
  result.arity = blk.matcher.get_arity()

proc to_callable*(value: Value): Callable =
  case value.kind:
  of VkFunction:
    return value.ref.fn.to_callable()
  of VkNativeFn:
    return to_callable(value.ref.native_fn)
  of VkBlock:
    return value.ref.block.to_callable()
  else:
    not_allowed("Cannot convert " & $value.kind & " to Callable")
