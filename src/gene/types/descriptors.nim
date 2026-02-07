## Built-in type registry: BUILTIN_TYPE_* constants, builtin_type_descs,
## lookup_builtin_type, set_expected_type_id.
## Included from type_defs.nim — shares its scope.

#################### Built-in Type Registry ####################

const
  BUILTIN_TYPE_ANY_ID*: TypeId = 0
  BUILTIN_TYPE_INT_ID*: TypeId = 1
  BUILTIN_TYPE_FLOAT_ID*: TypeId = 2
  BUILTIN_TYPE_STRING_ID*: TypeId = 3
  BUILTIN_TYPE_BOOL_ID*: TypeId = 4
  BUILTIN_TYPE_NIL_ID*: TypeId = 5
  BUILTIN_TYPE_SYMBOL_ID*: TypeId = 6
  BUILTIN_TYPE_CHAR_ID*: TypeId = 7
  BUILTIN_TYPE_ARRAY_ID*: TypeId = 8
  BUILTIN_TYPE_MAP_ID*: TypeId = 9
  BUILTIN_TYPE_COUNT* = 10

proc builtin_type_descs*(): seq[TypeDesc] =
  ## Return the pre-created TypeDesc objects for all built-in types.
  ## Index positions match the BUILTIN_TYPE_*_ID constants.
  @[
    TypeDesc(kind: TdkAny),                           # 0 = Any
    TypeDesc(kind: TdkNamed, name: "Int"),             # 1 = Int
    TypeDesc(kind: TdkNamed, name: "Float"),           # 2 = Float
    TypeDesc(kind: TdkNamed, name: "String"),          # 3 = String
    TypeDesc(kind: TdkNamed, name: "Bool"),            # 4 = Bool
    TypeDesc(kind: TdkNamed, name: "Nil"),             # 5 = Nil
    TypeDesc(kind: TdkNamed, name: "Symbol"),          # 6 = Symbol
    TypeDesc(kind: TdkNamed, name: "Char"),            # 7 = Char
    TypeDesc(kind: TdkNamed, name: "Array"),           # 8 = Array
    TypeDesc(kind: TdkNamed, name: "Map"),             # 9 = Map
  ]

proc lookup_builtin_type*(name: string): TypeId =
  ## Look up a built-in type name and return its TypeId.
  ## Returns NO_TYPE_ID if name is not a built-in type.
  case name
  of "Any": BUILTIN_TYPE_ANY_ID
  of "Int", "int", "Int64", "int64", "i64": BUILTIN_TYPE_INT_ID
  of "Float", "float", "Float64", "float64", "f64": BUILTIN_TYPE_FLOAT_ID
  of "String", "string": BUILTIN_TYPE_STRING_ID
  of "Bool", "bool": BUILTIN_TYPE_BOOL_ID
  of "Nil", "nil": BUILTIN_TYPE_NIL_ID
  of "Symbol": BUILTIN_TYPE_SYMBOL_ID
  of "Char": BUILTIN_TYPE_CHAR_ID
  of "Array": BUILTIN_TYPE_ARRAY_ID
  of "Map": BUILTIN_TYPE_MAP_ID
  else: NO_TYPE_ID

proc set_expected_type_id*(tracker: ScopeTracker, index: int16,
                          expected_type_id: TypeId) {.inline.} =
  ## Store a TypeId expectation for a variable slot in the scope tracker.
  if tracker == nil or expected_type_id == NO_TYPE_ID:
    return
  while tracker.type_expectation_ids.len <= index.int:
    tracker.type_expectation_ids.add(NO_TYPE_ID)
  tracker.type_expectation_ids[index.int] = expected_type_id
