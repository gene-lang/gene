import tables

import ../types

const
  InterceptFnArityMarker = "[GENE.INTERCEPT.FN_ARITY]"
  InterceptKeywordUnsupportedMarker = "[GENE.INTERCEPT.KEYWORD_UNSUPPORTED]"
  InterceptFnTargetMarker = "[GENE.INTERCEPT.FN_TARGET]"
  InterceptClassTargetMarker = "[GENE.INTERCEPT.CLASS_TARGET]"
  InterceptMappingArityMarker = "[GENE.INTERCEPT.MAPPING_ARITY]"
  InterceptMappingNameMarker = "[GENE.INTERCEPT.MAPPING_NAME]"
  InterceptMissingMethodMarker = "[GENE.INTERCEPT.MISSING_METHOD]"
  InterceptMacroUnsupportedMarker = "[GENE.INTERCEPT.MACRO_UNSUPPORTED]"
  InterceptAsyncUnsupportedMarker = "[GENE.INTERCEPT.ASYNC_UNSUPPORTED]"

proc interception_application_label(label: string, definition_name: string): string =
  if definition_name.len > 0:
    label & " '" & definition_name & "'"
  else:
    label

proc raise_interception_diagnostic(marker: string, label: string, definition_name: string, detail: string) =
  not_allowed(marker & " " & interception_application_label(label, definition_name) & ": " & detail)

proc matcher_name(matcher: Matcher): string =
  if matcher != nil and matcher.name_key != Key(0):
    try:
      return cast[Value](matcher.name_key).str
    except CatchableError:
      discard
  "<keyword>"

proc function_keyword_param_name(fn: Function): string =
  if fn != nil and fn.matcher != nil:
    for matcher in fn.matcher.children:
      if matcher.kind == MatchProp or matcher.is_prop:
        return matcher_name(matcher)
  ""

proc function_target_kind(fn_arg: Value): string =
  case fn_arg.kind
  of VkFunction:
    let fn = fn_arg.ref.fn
    if fn.is_macro_like:
      "macro-like function"
    elif fn.async:
      "async function"
    elif function_keyword_param_name(fn).len > 0:
      "function with keyword parameters"
    else:
      "function"
  of VkNativeFn:
    "native function"
  of VkNativeMacro:
    "native macro"
  of VkInterception:
    "interception"
  of VkClass:
    "class"
  else:
    $fn_arg.kind

proc normalize_advice_args(args_val: Value): Value =
  var normalized = new_array_value()
  case args_val.kind
  of VkArray:
    let src = array_data(args_val)
    if src.len == 0:
      array_data(normalized).add("self".to_symbol_value())
    elif src[0].kind == VkSymbol and src[0].str == "self":
      for arg in src:
        array_data(normalized).add(arg)
    else:
      array_data(normalized).add("self".to_symbol_value())
      for arg in src:
        array_data(normalized).add(arg)
  of VkSymbol:
    if args_val.str == "_" or args_val.str == "self":
      array_data(normalized).add("self".to_symbol_value())
    else:
      array_data(normalized).add("self".to_symbol_value())
      array_data(normalized).add(args_val)
  else:
    not_allowed("advice arguments must be an array or symbol")
  normalized

proc advice_user_arg_count(args_val: Value): int =
  case args_val.kind
  of VkArray:
    return array_data(args_val).len
  of VkSymbol:
    if args_val.str == "_" or args_val.str == "self":
      return 0
    return 1
  else:
    not_allowed("advice arguments must be an array or symbol")
    return 0

proc resolve_advice_callable(callable_val: Value, caller_frame: Frame): Value =
  case callable_val.kind
  of VkFunction, VkNativeFn:
    return callable_val
  of VkSymbol:
    let key = callable_val.str.to_key()
    var resolved = NIL
    if caller_frame != nil and caller_frame.scope != nil and caller_frame.scope.tracker != nil:
      let found = caller_frame.scope.tracker.locate(key)
      if found.local_index >= 0:
        var scope = caller_frame.scope
        var parent_index = found.parent_index
        while parent_index > 0 and scope != nil:
          parent_index.dec()
          scope = scope.parent
        if scope != nil and found.local_index < scope.members.len:
          resolved = scope.members[found.local_index]
    if resolved == NIL:
      resolved = if caller_frame.ns != nil: caller_frame.ns[key] else: NIL
    if resolved == NIL:
      resolved = App.app.global_ns.ref.ns[key]
    if resolved == NIL:
      resolved = App.app.gene_ns.ref.ns[key]
    if resolved == NIL:
      resolved = App.app.genex_ns.ref.ns[key]
    if resolved == NIL:
      not_allowed("advice callable not found: " & callable_val.str)
    if resolved.kind notin {VkFunction, VkNativeFn}:
      not_allowed("advice callable must be a function or native function")
    return resolved
  else:
    not_allowed("advice callable must be a symbol")

proc parse_interceptor_macro(form_label: string, definition_kind: InterceptorDefinitionKind,
                        vm: ptr VirtualMachine, gene_value: Value, caller_frame: Frame): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    let gene = gene_value.gene
    if gene.children.len < 2:
      not_allowed(form_label & " requires a name and interceptor parameters")

    let name_val = gene.children[0]
    if name_val.kind != VkSymbol:
      not_allowed(form_label & " name must be a symbol")
    let name = name_val.str

    let params_val = gene.children[1]
    if params_val.kind != VkArray:
      not_allowed(form_label & " parameter list must be an array")

    var param_names: seq[string] = @[]
    for p in array_data(params_val):
      if p.kind == VkSymbol:
        param_names.add(p.str)
      else:
        not_allowed(form_label & " parameter must be a symbol")

    if definition_kind == IdkFunctionInterceptor and param_names.len != 1:
      not_allowed("fn-interceptor parameter list must contain exactly one symbol")

    let definition = InterceptorDefinition(
      name: name,
      definition_kind: definition_kind,
      param_names: param_names,
      before_advices: initTable[string, seq[Value]](),
      invariant_advices: initTable[string, seq[Value]](),
      after_advices: initTable[string, seq[InterceptionAfterAdvice]](),
      around_advices: initTable[string, Value](),
      before_filter_advices: initTable[string, seq[Value]](),
      enabled: true
    )

    for i in 2..<gene.children.len:
      let advice_def = gene.children[i]
      if advice_def.kind != VkGene:
        not_allowed(form_label & " advice definition must be a gene expression")

      let advice_gene = advice_def.gene
      if advice_gene.children.len < 2:
        not_allowed(form_label & " advice requires type and target")

      let advice_type = advice_gene.type
      if advice_type.kind != VkSymbol:
        not_allowed(form_label & " advice type must be a symbol")
      let advice_type_str = advice_type.str

      var replace_result = false
      let replace_key = "replace_result".to_key()
      if advice_gene.props.has_key(replace_key):
        let replace_val = advice_gene.props[replace_key]
        replace_result = (replace_val == NIL or replace_val == PLACEHOLDER) or replace_val.to_bool()
        if replace_result and advice_type_str != "after":
          not_allowed("replace_result is only allowed for after " & form_label & " advices")

      let target = advice_gene.children[0]
      if target.kind != VkSymbol:
        not_allowed(form_label & " advice target must be an interceptor parameter symbol")
      let target_name = target.str

      if not (target_name in param_names):
        not_allowed(form_label & " advice target '" & target_name & "' is not a defined interceptor parameter")

      var advice_val: Value
      var user_arg_count = -1
      if advice_gene.children.len == 2:
        advice_val = resolve_advice_callable(advice_gene.children[1], caller_frame)
      else:
        user_arg_count = advice_user_arg_count(advice_gene.children[1])
        let matcher = new_arg_matcher()
        let matcher_args = normalize_advice_args(advice_gene.children[1])
        matcher.parse(matcher_args)
        matcher.check_hint()

        var body: seq[Value] = @[]
        for j in 2..<advice_gene.children.len:
          body.add(advice_gene.children[j])

        let advice_fn = new_fn(advice_type_str & "_advice", matcher, body)
        advice_fn.ns = caller_frame.ns
        advice_fn.parent_scope = caller_frame.scope

        let parent_tracker =
          if caller_frame != nil and caller_frame.scope != nil:
            caller_frame.scope.tracker
          else:
            nil
        var scope_tracker =
          if parent_tracker != nil:
            new_scope_tracker(parent_tracker)
          else:
            new_scope_tracker()
        for m in matcher.children:
          if m.kind == MatchData and m.name_key != Key(0):
            scope_tracker.add(m.name_key)
        advice_fn.scope_tracker = scope_tracker

        let advice_fn_ref = new_ref(VkFunction)
        advice_fn_ref.fn = advice_fn
        advice_val = advice_fn_ref.to_ref_value()

      case advice_type_str:
      of "before":
        if not definition.before_advices.hasKey(target_name):
          definition.before_advices[target_name] = @[]
        definition.before_advices[target_name].add(advice_val)
      of "after":
        if not definition.after_advices.hasKey(target_name):
          definition.after_advices[target_name] = @[]
        definition.after_advices[target_name].add(InterceptionAfterAdvice(
          callable: advice_val,
          replace_result: replace_result,
          user_arg_count: user_arg_count
        ))
      of "invariant":
        if not definition.invariant_advices.hasKey(target_name):
          definition.invariant_advices[target_name] = @[]
        definition.invariant_advices[target_name].add(advice_val)
      of "around":
        if definition.around_advices.hasKey(target_name):
          not_allowed("around advice already defined for '" & target_name & "'")
        definition.around_advices[target_name] = advice_val
      of "before_filter":
        if not definition.before_filter_advices.hasKey(target_name):
          definition.before_filter_advices[target_name] = @[]
        definition.before_filter_advices[target_name].add(advice_val)
      else:
        not_allowed("unknown " & form_label & " advice type: " & advice_type_str)

    let interceptor_ref = new_ref(VkInterceptor)
    interceptor_ref.interceptor = definition
    let definition_val = interceptor_ref.to_ref_value()

    caller_frame.ns[name.to_key()] = definition_val

    return definition_val

proc interceptor_macro(vm: ptr VirtualMachine, gene_value: Value, caller_frame: Frame): Value {.gcsafe.} =
  parse_interceptor_macro("interceptor", IdkClassInterceptor, vm, gene_value, caller_frame)

proc fn_interceptor_macro(vm: ptr VirtualMachine, gene_value: Value, caller_frame: Frame): Value {.gcsafe.} =
  parse_interceptor_macro("fn-interceptor", IdkFunctionInterceptor, vm, gene_value, caller_frame)

proc create_interception_value(original: Value, definition_value: Value, param_name: string): Value =
  let interception = Interception(
    original: original,
    definition: definition_value,
    param_name: param_name,
    active: true
  )
  let interception_ref = new_ref(VkInterception)
  interception_ref.interception = interception
  interception_ref.to_ref_value()

type
  ClassInterceptorMapping = object
    param_name: string
    method_name: string
    method_key: Key

proc class_target_kind(target: Value): string =
  case target.kind
  of VkClass:
    "class"
  of VkFunction:
    if target.ref.fn.is_macro_like:
      "macro-like function"
    else:
      "function"
  of VkNativeFn:
    "native function"
  of VkNativeMacro:
    "native macro"
  of VkInterception:
    "interception"
  else:
    $target.kind

proc validate_class_interceptor_target(label: string, definition_name: string, class_arg: Value): Class =
  case class_arg.kind
  of VkClass:
    return class_arg.ref.class
  of VkFunction:
    let fn = class_arg.ref.fn
    if fn.is_macro_like:
      raise_interception_diagnostic(
        InterceptMacroUnsupportedMarker,
        label,
        definition_name,
        "expected class target; actual " & class_target_kind(class_arg) & " '" & fn.name & "'"
      )
  of VkNativeMacro:
    raise_interception_diagnostic(
      InterceptMacroUnsupportedMarker,
      label,
      definition_name,
      "expected class target; actual " & class_target_kind(class_arg)
    )
  else:
    discard

  raise_interception_diagnostic(
    InterceptClassTargetMarker,
    label,
    definition_name,
    "expected class target; actual " & class_target_kind(class_arg)
  )
  nil

proc prevalidate_class_interceptor_mappings(label: string, definition: InterceptorDefinition, target_class: Class,
                                            method_name_vals: seq[Value]): seq[ClassInterceptorMapping] =
  if method_name_vals.len != definition.param_names.len:
    raise_interception_diagnostic(
      InterceptMappingArityMarker,
      label,
      definition.name,
      "expected " & $definition.param_names.len & " method mapping arguments; actual " & $method_name_vals.len
    )

  for i in 0..<definition.param_names.len:
    let param_name = definition.param_names[i]
    let method_name_val = method_name_vals[i]
    var method_name = ""
    case method_name_val.kind
    of VkString, VkSymbol:
      method_name = method_name_val.str
    else:
      raise_interception_diagnostic(
        InterceptMappingNameMarker,
        label,
        definition.name,
        "mapping for parameter '" & param_name & "' expected string or symbol method name; actual " &
          $method_name_val.kind
      )

    let method_key = method_name.to_key()
    if not target_class.methods.hasKey(method_key):
      raise_interception_diagnostic(
        InterceptMissingMethodMarker,
        label,
        definition.name,
        "class '" & target_class.name & "' has no method '" & method_name &
          "' for parameter '" & param_name & "'"
      )

    result.add(ClassInterceptorMapping(
      param_name: param_name,
      method_name: method_name,
      method_key: method_key
    ))

proc apply_interceptor_to_class(label: string, self: Value, class_arg: Value, method_name_vals: seq[Value]): Value =
  if self.kind != VkInterceptor:
    not_allowed(label & " must be called on an interceptor")

  let definition = self.ref.interceptor
  let target_class = validate_class_interceptor_target(label, definition.name, class_arg)
  let mappings = prevalidate_class_interceptor_mappings(label, definition, target_class, method_name_vals)

  let applied = new_array_value()
  for mapping in mappings:
    let original_method = target_class.methods[mapping.method_key]
    let interception_val = create_interception_value(original_method.callable, self, mapping.param_name)
    target_class.methods[mapping.method_key].callable = interception_val
    target_class.version.inc()
    if target_class.runtime_type != nil:
      target_class.runtime_type.methods[mapping.method_key] = interception_val
    array_data(applied).add(interception_val)

  return applied

proc validate_function_interceptor_target(label: string, definition_name: string, fn_arg: Value) =
  case fn_arg.kind
  of VkFunction:
    let fn = fn_arg.ref.fn
    if fn.is_macro_like:
      raise_interception_diagnostic(
        InterceptMacroUnsupportedMarker,
        label,
        definition_name,
        "expected non-macro callable target; actual " & function_target_kind(fn_arg) &
          " '" & fn.name & "'"
      )
    if fn.async:
      raise_interception_diagnostic(
        InterceptAsyncUnsupportedMarker,
        label,
        definition_name,
        "expected synchronous callable target; actual async function '" & fn.name & "'"
      )
    let keyword_name = function_keyword_param_name(fn)
    if keyword_name.len > 0:
      raise_interception_diagnostic(
        InterceptKeywordUnsupportedMarker,
        label,
        definition_name,
        "target function '" & fn.name & "' declares keyword parameter '" & keyword_name &
          "', but keyword forwarding is deferred"
      )
  of VkNativeFn, VkInterception:
    discard
  of VkNativeMacro:
    raise_interception_diagnostic(
      InterceptMacroUnsupportedMarker,
      label,
      definition_name,
      "expected non-macro callable target; actual " & function_target_kind(fn_arg)
    )
  else:
    raise_interception_diagnostic(
      InterceptFnTargetMarker,
      label,
      definition_name,
      "expected function, native function, or interception target; actual " & function_target_kind(fn_arg)
    )

proc apply_interceptor_to_function(label: string, self: Value, fn_arg: Value): Value =
  if self.kind != VkInterceptor:
    not_allowed(label & " must be called on an interceptor")

  let definition = self.ref.interceptor
  if definition.param_names.len != 1:
    raise_interception_diagnostic(
      InterceptFnArityMarker,
      label,
      definition.name,
      "expected exactly one function parameter in interceptor definition; actual " & $definition.param_names.len
    )

  validate_function_interceptor_target(label, definition.name, fn_arg)

  create_interception_value(fn_arg, self, definition.param_names[0])

proc collect_class_application_args(label: string, definition_name: string, args: ptr UncheckedArray[Value],
                                    arg_count: int, has_keyword_args: bool): tuple[class_arg: Value,
                                    method_name_vals: seq[Value]] =
  if has_keyword_args:
    raise_interception_diagnostic(
      InterceptKeywordUnsupportedMarker,
      label,
      definition_name,
      "class interceptor application does not accept keyword arguments"
    )

  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional < 2:
    raise_interception_diagnostic(
      InterceptClassTargetMarker,
      label,
      definition_name,
      "expected class target argument; actual none"
    )

  result.class_arg = get_positional_arg(args, 1, has_keyword_args)
  result.method_name_vals = @[]
  for i in 2..<positional:
    result.method_name_vals.add(get_positional_arg(args, i, has_keyword_args))

proc interceptor_call(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  let self = get_positional_arg(args, 0, has_keyword_args)
  if self.kind != VkInterceptor:
    not_allowed("interceptor call must be called on an interceptor")

  let definition = self.ref.interceptor
  case definition.definition_kind
  of IdkFunctionInterceptor:
    if has_keyword_args:
      raise_interception_diagnostic(
        InterceptKeywordUnsupportedMarker,
        "fn-interceptor application",
        definition.name,
        "direct application does not accept keyword arguments"
      )
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional != 2:
      raise_interception_diagnostic(
        InterceptFnArityMarker,
        "fn-interceptor application",
        definition.name,
        "expected exactly one callable argument; actual " & $(positional - 1)
      )
    let fn_arg = get_positional_arg(args, 1, has_keyword_args)
    apply_interceptor_to_function("fn-interceptor application", self, fn_arg)
  of IdkClassInterceptor:
    let collected = collect_class_application_args("interceptor application", definition.name, args, arg_count, has_keyword_args)
    apply_interceptor_to_class("interceptor application", self, collected.class_arg, collected.method_name_vals)

proc toggle_receiver(label: string, args: ptr UncheckedArray[Value], arg_count: int,
                     has_keyword_args: bool): Value {.gcsafe.} =
  if has_keyword_args:
    not_allowed(label & " does not accept keyword arguments")
  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional != 1:
    not_allowed(label & " expects no arguments")
  get_positional_arg(args, 0, has_keyword_args)

proc interceptor_set_enabled(label: string, args: ptr UncheckedArray[Value], arg_count: int,
                        has_keyword_args: bool, enabled: bool): Value {.gcsafe.} =
  let self = toggle_receiver(label, args, arg_count, has_keyword_args)
  if self.kind != VkInterceptor:
    not_allowed(label & " must be called on an interceptor")
  self.ref.interceptor.enabled = enabled
  self

proc interceptor_enable(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                   has_keyword_args: bool): Value {.gcsafe.} =
  interceptor_set_enabled("Interceptor.enable", args, arg_count, has_keyword_args, true)

proc interceptor_disable(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                    has_keyword_args: bool): Value {.gcsafe.} =
  interceptor_set_enabled("Interceptor.disable", args, arg_count, has_keyword_args, false)

proc interception_set_active(label: string, args: ptr UncheckedArray[Value], arg_count: int,
                             has_keyword_args: bool, active: bool): Value {.gcsafe.} =
  let self = toggle_receiver(label, args, arg_count, has_keyword_args)
  if self.kind != VkInterception:
    not_allowed(label & " must be called on an Interception")
  self.ref.interception.active = active
  self

proc interception_enable(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                         has_keyword_args: bool): Value {.gcsafe.} =
  interception_set_active("Interception.enable", args, arg_count, has_keyword_args, true)

proc interception_disable(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                          has_keyword_args: bool): Value {.gcsafe.} =
  interception_set_active("Interception.disable", args, arg_count, has_keyword_args, false)

proc init_interception_support*() =
  var global_ns = App.app.global_ns.ns

  var interceptor_macro_ref = new_ref(VkNativeMacro)
  interceptor_macro_ref.native_macro = interceptor_macro
  global_ns["interceptor".to_key()] = interceptor_macro_ref.to_ref_value()

  var fn_interceptor_macro_ref = new_ref(VkNativeMacro)
  fn_interceptor_macro_ref.native_macro = fn_interceptor_macro
  global_ns["fn-interceptor".to_key()] = fn_interceptor_macro_ref.to_ref_value()

  let interceptor_class = new_class("Interceptor")
  if App.app.object_class.kind == VkClass:
    interceptor_class.parent = App.app.object_class.ref.class
  interceptor_class.def_native_method("call", interceptor_call)
  interceptor_class.def_native_method("enable", interceptor_enable)
  interceptor_class.def_native_method("disable", interceptor_disable)
  var interceptor_class_ref = new_ref(VkClass)
  interceptor_class_ref.class = interceptor_class
  App.app.interceptor_class = interceptor_class_ref.to_ref_value()
  App.app.gene_ns.ns["Interceptor".to_key()] = App.app.interceptor_class
  global_ns["Interceptor".to_key()] = App.app.interceptor_class

  let interception_class = new_class("Interception")
  if App.app.object_class.kind == VkClass:
    interception_class.parent = App.app.object_class.ref.class
  interception_class.def_native_method("enable", interception_enable)
  interception_class.def_native_method("disable", interception_disable)
  var interception_class_ref = new_ref(VkClass)
  interception_class_ref.class = interception_class
  App.app.interception_class = interception_class_ref.to_ref_value()
  App.app.gene_ns.ns["Interception".to_key()] = App.app.interception_class
  global_ns["Interception".to_key()] = App.app.interception_class
