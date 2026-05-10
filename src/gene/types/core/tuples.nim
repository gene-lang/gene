## Tuple operations
## Included from core.nim — shares its scope.

proc copy_tuple_type_descs(type_descs: seq[TypeDesc]): seq[TypeDesc] =
  if type_descs.len == 0:
    return @[]
  result = newSeqOfCap[TypeDesc](type_descs.len)
  for desc in type_descs:
    result.add(desc)

proc tuple_type_descs_for(field_type_ids: seq[TypeId], field_type_descs: seq[TypeDesc]): seq[TypeDesc] =
  if field_type_descs.len > 0:
    return copy_tuple_type_descs(field_type_descs)

  for type_id in field_type_ids:
    if type_id != NO_TYPE_ID:
      return builtin_type_descs()

  @[]

proc infer_tuple_payload_shape(fields: seq[string], field_type_ids: seq[TypeId],
                               payload_shape: EnumPayloadShapeKind,
                               payload_arity: int): tuple[shape: EnumPayloadShapeKind, arity: int] =
  result.arity = payload_arity
  if result.arity < 0:
    if fields.len > 0:
      result.arity = fields.len
    elif field_type_ids.len > 0:
      result.arity = field_type_ids.len
    else:
      result.arity = 0

  result.shape = payload_shape
  if result.shape == EpsUnit and result.arity > 0:
    result.shape = if fields.len > 0: EpsNamed else: EpsPositional
  elif result.arity == 0:
    result.shape = EpsUnit

proc validate_tuple_metadata_parts(name: string,
                                   fields: seq[string],
                                   field_type_ids: seq[TypeId],
                                   field_type_descs: seq[TypeDesc],
                                   payload_shape: EnumPayloadShapeKind,
                                   payload_arity: int,
                                   context: string) =
  if name.len == 0:
    not_allowed(context & " requires a tuple name")
  if payload_arity < 0:
    not_allowed(context & " payload arity must not be negative")

  case payload_shape
  of EpsNamed:
    if fields.len != payload_arity:
      not_allowed(context & " named payload metadata count " & $fields.len &
                  " does not match payload arity " & $payload_arity)
  of EpsPositional:
    if fields.len != 0:
      not_allowed(context & " positional payload metadata must not contain field names")
  of EpsUnit:
    if fields.len != 0 or payload_arity != 0:
      not_allowed(context & " unit payload metadata must be empty")

  if field_type_ids.len != payload_arity:
    not_allowed(context & " field type metadata count " & $field_type_ids.len &
                " does not match payload arity " & $payload_arity)

  for i, type_id in field_type_ids:
    if type_id == NO_TYPE_ID:
      continue
    let label =
      if payload_shape == EpsNamed and i >= 0 and i < fields.len:
        fields[i]
      else:
        "#" & $i
    if type_id < 0:
      not_allowed(context & " field " & label & " has invalid TypeId " & $type_id)
    if field_type_descs.len == 0 or type_id.int >= field_type_descs.len:
      not_allowed(context & " field " & label & " TypeId " & $type_id &
                  " has no matching type descriptor")

proc tuple_payload_arity*(tuple_def: TupleDef): int {.inline.} =
  if tuple_def == nil:
    return 0
  if tuple_def.payload_arity > 0:
    return tuple_def.payload_arity
  if tuple_def.fields.len > 0:
    return tuple_def.fields.len
  tuple_def.field_type_ids.len

proc tuple_payload_shape*(tuple_def: TupleDef): EnumPayloadShapeKind {.inline.} =
  if tuple_def == nil:
    return EpsUnit
  let arity = tuple_payload_arity(tuple_def)
  if arity == 0:
    return EpsUnit
  if tuple_def.payload_shape != EpsUnit:
    return tuple_def.payload_shape
  if tuple_def.fields.len > 0:
    return EpsNamed
  EpsPositional

proc tuple_payload_slot_label*(tuple_def: TupleDef, index: int): string =
  if tuple_def != nil and tuple_payload_shape(tuple_def) == EpsNamed and
      index >= 0 and index < tuple_def.fields.len:
    return tuple_def.fields[index]
  "#" & $index

proc validate_tuple_metadata*(tuple_def: TupleDef, context = "TupleDef") =
  if tuple_def == nil:
    not_allowed(context & " requires tuple metadata")
  validate_tuple_metadata_parts(
    tuple_def.name,
    tuple_def.fields,
    tuple_def.field_type_ids,
    tuple_def.field_type_descs,
    tuple_def.payload_shape,
    tuple_def.payload_arity,
    context & " " & tuple_def.name,
  )

proc new_tuple_def*(name: string,
                    fields: seq[string] = @[],
                    field_type_ids: seq[TypeId] = @[],
                    field_type_descs: seq[TypeDesc] = @[],
                    payload_shape: EnumPayloadShapeKind = EpsUnit,
                    payload_arity: int = -1,
                    module_path: string = "",
                    internal_path: string = ""): TupleDef =
  let inferred = infer_tuple_payload_shape(fields, field_type_ids, payload_shape, payload_arity)
  var tuple_type_ids = field_type_ids
  if tuple_type_ids.len == 0 and inferred.arity > 0:
    tuple_type_ids = newSeq[TypeId](inferred.arity)
    for i in 0..<tuple_type_ids.len:
      tuple_type_ids[i] = NO_TYPE_ID
  let descs = tuple_type_descs_for(tuple_type_ids, field_type_descs)
  validate_tuple_metadata_parts(name, fields, tuple_type_ids, descs,
                                inferred.shape, inferred.arity,
                                "tuple " & name)
  TupleDef(
    name: name,
    module_path: module_path,
    internal_path: internal_path,
    payload_shape: inferred.shape,
    payload_arity: inferred.arity,
    fields: fields,
    field_type_ids: tuple_type_ids,
    field_type_descs: descs,
  )

proc to_value*(tuple_def: TupleDef): Value =
  validate_tuple_metadata(tuple_def)
  let r = new_ref(VkTupleDef)
  r.tuple_def = tuple_def
  r.to_ref_value()

proc new_tuple_value*(tuple_def_value: Value, data: seq[Value]): Value =
  if tuple_def_value.kind != VkTupleDef or tuple_def_value.ref == nil or tuple_def_value.ref.tuple_def == nil:
    not_allowed("TupleValue requires a tuple definition")
  let tuple_def = tuple_def_value.ref.tuple_def
  validate_tuple_metadata(tuple_def, "TupleValue")
  let expected = tuple_payload_arity(tuple_def)
  if data.len != expected:
    let field_names = if expected > 0 and tuple_payload_shape(tuple_def) == EpsNamed: " (" & tuple_def.fields.join(", ") & ")" else: ""
    not_allowed("TupleValue " & tuple_def.name & " expects " & $expected &
                " payload value(s)" & field_names & ", got " & $data.len)

  let r = new_ref(VkTupleValue)
  r.tv_def = tuple_def_value
  r.tv_data = data
  r.to_ref_value()
