{.push warning[ResultShadowed]: off.}

# Shared database types and utilities for Gene database clients

import tables
export tables

# For static linking, don't include boilerplate to avoid duplicate set_globals
when defined(noExtensions):
  include ../gene/extension/boilerplate
else:
  # Statically linked - just import types directly
  import ../gene/types

# Base type for all database connections
type
  DatabaseConnection* = ref object of RootObj
    closed*: bool

# Collect positional arguments after a given start index
proc collect_params*(args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool, start_idx: int): seq[Value] =
  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional <= start_idx:
    return @[]
  result = @[]
  for i in start_idx..<positional:
    result.add(get_positional_arg(args, i, has_keyword_args))

# Convert Gene Value to SQL parameter based on type
# Note: Each database module must provide its own bind_gene_param
# implementation since prepared statement types are different

# Collect positional arguments after a given start index (duplicate for convenience)
proc collect_params_after*(args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool, start_idx: int): seq[Value] =
  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional <= start_idx:
    return @[]
  result = @[]
  for i in start_idx..<positional:
    result.add(get_positional_arg(args, i, has_keyword_args))

{.pop.}
