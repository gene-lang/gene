import tables, sets
import ../types

proc resolve_property_instance(scope: Scope): Value =
  if scope.is_nil or scope.tracker.is_nil:
    return NIL
  let selfKey = "self".to_key()
  if scope.tracker.mappings.hasKey(selfKey):
    let idx = scope.tracker.mappings[selfKey]
    if idx.int < scope.members.len:
      return scope.members[idx.int]
  NIL

proc assign_property_params*(matcher: RootMatcher, scope: Scope, explicit_instance: Value = NIL) =
  ## Assign shorthand property parameters (e.g. [/x]) directly onto the instance.
  if matcher.is_nil or scope.is_nil or matcher.children.len == 0:
    return

  var instance = explicit_instance
  if instance == NIL:
    instance = resolve_property_instance(scope)

  if instance.kind != VkInstance:
    return

  for i, param in matcher.children:
    if param.is_prop and i < scope.members.len:
      let value = scope.members[i]
      if value.kind != VkNil:
        instance.ref.instance_props[param.name_key] = value

# Forward declaration for original process_args function
proc process_args*(matcher: RootMatcher, args: Value, scope: Scope)

# Optimized version for zero arguments
proc process_args_zero*(matcher: RootMatcher, scope: Scope) {.inline.} =
  ## Ultra-fast path for zero-argument functions
  while scope.members.len < matcher.children.len:
    scope.members.add(NIL)

  # Apply default values or empty arrays for rest parameters
  for i, param in matcher.children:
    if param.is_splat:
      # Rest parameter with no arguments gets empty array
      scope.members[i] = new_array_value()
    elif param.default_value.kind != VkNil:
      scope.members[i] = param.default_value

  assign_property_params(matcher, scope)

# Optimized version for single argument
proc process_args_one*(matcher: RootMatcher, arg: Value, scope: Scope) {.inline.} =
  ## Ultra-fast path for single-argument functions
  while scope.members.len < matcher.children.len:
    scope.members.add(NIL)

  if matcher.children.len > 0:
    let first_param = matcher.children[0]
    if first_param.is_splat:
      # First parameter is rest - collect the single arg into an array
      let rest_array = new_array_value()
      rest_array.ref.arr.add(arg)
      scope.members[0] = rest_array
      # Rest parameters for remaining params
      for i in 1..<matcher.children.len:
        let param = matcher.children[i]
        if param.is_splat:
          scope.members[i] = new_array_value()
        elif param.default_value.kind != VkNil:
          scope.members[i] = param.default_value
    else:
      scope.members[0] = arg
      # Apply defaults or empty arrays for remaining parameters
      for i in 1..<matcher.children.len:
        let param = matcher.children[i]
        if param.is_splat:
          scope.members[i] = new_array_value()
        elif param.default_value.kind != VkNil:
          scope.members[i] = param.default_value
  assign_property_params(matcher, scope)

proc process_args_direct*(matcher: RootMatcher, args: ptr UncheckedArray[Value],
                         arg_count: int, has_keyword_args: bool, scope: Scope) {.inline.} =
  ## Process arguments directly from stack to scope
  ## Supports positional and keyword (property) arguments.

  # Pure positional fast path
  while scope.members.len < matcher.children.len:
    scope.members.add(NIL)
  for i in 0..<matcher.children.len:
    scope.members[i] = NIL

  if arg_count == 0:
    for i, param in matcher.children:
      if param.is_splat:
        scope.members[i] = new_array_value()
      elif param.default_value.kind != VkNil:
        scope.members[i] = param.default_value
    assign_property_params(matcher, scope)
    return

  var pos_index = 0
  for i, param in matcher.children:
    if param.is_splat:
      let rest_array = new_array_value()
      while pos_index < arg_count:
        rest_array.ref.arr.add(args[pos_index])
        pos_index.inc()
      scope.members[i] = rest_array
    elif pos_index < arg_count:
      scope.members[i] = args[pos_index]
      pos_index.inc()
    elif param.default_value.kind != VkNil:
      scope.members[i] = param.default_value

  assign_property_params(matcher, scope)

proc process_args_direct_kw*(matcher: RootMatcher, positional: ptr UncheckedArray[Value],
                            pos_count: int, keywords: seq[(Key, Value)],
                            scope: Scope) {.inline.} =
  ## Optimized processing when keyword arguments are provided separately.
  while scope.members.len < matcher.children.len:
    scope.members.add(NIL)
  for i in 0..<matcher.children.len:
    scope.members[i] = NIL

  var used_indices = initHashSet[int]()
  if keywords.len > 0:
    var kw_table = initTable[Key, Value]()
    for (k, v) in keywords:
      kw_table[k] = v

    for i, param in matcher.children:
      if param.is_prop and kw_table.hasKey(param.name_key):
        scope.members[i] = kw_table[param.name_key]
        used_indices.incl(i)

  var pos_index = 0
  for i, param in matcher.children:
    if i in used_indices:
      continue
    if param.is_splat:
      let rest_array = new_array_value()
      while pos_index < pos_count:
        rest_array.ref.arr.add(positional[pos_index])
        pos_index.inc()
      scope.members[i] = rest_array
    elif pos_index < pos_count:
      scope.members[i] = positional[pos_index]
      pos_index.inc()
    elif param.default_value.kind != VkNil:
      scope.members[i] = param.default_value

  assign_property_params(matcher, scope)

proc process_args*(matcher: RootMatcher, args: Value, scope: Scope) =
  ## Process function arguments and bind them to the scope
  ## Handles both positional and named arguments
  
  
  # Ensure scope.members has enough slots for all parameters
  for i, param in matcher.children:
    scope.members.add(NIL)
  
  if args.kind != VkGene:
    # No arguments provided, use defaults or empty arrays for rest parameters
    for i, param in matcher.children:
      if param.is_splat:
        scope.members[i] = new_array_value()
      elif param.default_value.kind != VkNil:
        scope.members[i] = param.default_value
    return
  
  let positional = args.gene.children
  let named = args.gene.props
  
  # First pass: bind named arguments
  var used_indices = initHashSet[int]()
  for i, param in matcher.children:
    if param.is_prop and named.hasKey(param.name_key):
      # Named argument provided
      scope.members[i] = named[param.name_key]
      used_indices.incl(i)
  
  # Second pass: bind positional arguments
  var pos_index = 0
  for i, param in matcher.children:
    if i notin used_indices:
      if param.is_splat:
        # Rest parameter - collect all remaining positional arguments into an array
        let rest_array = new_array_value()
        while pos_index < positional.len:
          rest_array.ref.arr.add(positional[pos_index])
          pos_index.inc()
        scope.members[i] = rest_array
      elif pos_index < positional.len:
        # Fill in positional argument
        scope.members[i] = positional[pos_index]
        pos_index.inc()
      elif param.default_value.kind != VkNil:
        # Use default value
        scope.members[i] = param.default_value
      else:
        # No value provided and no default - keep as NIL
        discard

  assign_property_params(matcher, scope)
  
