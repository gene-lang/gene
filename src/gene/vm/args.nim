import ../types
import tables
import sets

# Forward declaration for original process_args function
proc process_args*(matcher: RootMatcher, args: Value, scope: Scope)

# Fast path: Direct stack-to-scope argument passing without Gene objects
proc process_args_direct*(matcher: RootMatcher, args: ptr UncheckedArray[Value],
                         arg_count: int, has_keyword_args: bool, scope: Scope) {.inline.} =
  ## Process function arguments directly from stack to scope
  ## Eliminates Gene object creation for better performance

  # Ensure scope.members has enough slots for all parameters
  while scope.members.len < matcher.children.len:
    scope.members.add(NIL)

  if arg_count == 0:
    # No arguments provided, use defaults where available
    for i, param in matcher.children:
      if param.default_value.kind != VkNil:
        scope.members[i] = param.default_value
    return

  # For now, handle only positional arguments (most common case)
  # TODO: Add keyword argument support later
  if not has_keyword_args:
    # Fast path: positional arguments only
    var pos_index = 0
    for i, param in matcher.children:
      if pos_index < arg_count:
        scope.members[i] = args[pos_index]
        pos_index.inc()
      elif param.default_value.kind != VkNil:
        scope.members[i] = param.default_value
  else:
    # Fallback to Gene-based processing for keyword arguments
    # TODO: Optimize this path later
    var args_gene = new_gene_value()
    for i in 0..<arg_count:
      args_gene.gene.children.add(args[i])
    process_args(matcher, args_gene, scope)

# Optimized version for zero arguments
proc process_args_zero*(matcher: RootMatcher, scope: Scope) {.inline.} =
  ## Ultra-fast path for zero-argument functions
  while scope.members.len < matcher.children.len:
    scope.members.add(NIL)

  # Apply default values
  for i, param in matcher.children:
    if param.default_value.kind != VkNil:
      scope.members[i] = param.default_value

# Optimized version for single argument
proc process_args_one*(matcher: RootMatcher, arg: Value, scope: Scope) {.inline.} =
  ## Ultra-fast path for single-argument functions
  while scope.members.len < matcher.children.len:
    scope.members.add(NIL)

  if matcher.children.len > 0:
    scope.members[0] = arg
    # Apply defaults for remaining parameters
    for i in 1..<matcher.children.len:
      let param = matcher.children[i]
      if param.default_value.kind != VkNil:
        scope.members[i] = param.default_value

proc process_args*(matcher: RootMatcher, args: Value, scope: Scope) =
  ## Process function arguments and bind them to the scope
  ## Handles both positional and named arguments
  
  
  # Ensure scope.members has enough slots for all parameters
  for i, param in matcher.children:
    scope.members.add(NIL)
  
  if args.kind != VkGene:
    # No arguments provided, use defaults where available
    for i, param in matcher.children:
      if param.default_value.kind != VkNil:
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
    if i notin used_indices and pos_index < positional.len:
      # Fill in positional argument
      scope.members[i] = positional[pos_index]
      pos_index.inc()
    elif i notin used_indices and param.default_value.kind != VkNil:
      # Use default value
      scope.members[i] = param.default_value
    elif i notin used_indices:
      # No value provided and no default - keep as NIL
      discard
  
