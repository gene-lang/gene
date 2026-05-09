## Enum operations
## Included from core.nim — shares its scope.

proc copy_enum_type_descs(type_descs: seq[TypeDesc]): seq[TypeDesc] =
  if type_descs.len == 0:
    return @[]
  result = newSeqOfCap[TypeDesc](type_descs.len)
  for desc in type_descs:
    result.add(desc)

proc new_enum*(name: string, type_params: seq[string] = @[], field_type_descs: seq[TypeDesc] = @[]): EnumDef =
  return EnumDef(
    name: name,
    type_params: type_params,
    members: initTable[string, EnumMember](),
    field_type_descs: copy_enum_type_descs(field_type_descs),
  )

proc infer_enum_payload_shape(fields: seq[string], field_type_ids: seq[TypeId],
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

proc enum_payload_arity*(member: EnumMember): int {.inline.} =
  if member == nil:
    return 0
  if member.payload_arity > 0:
    return member.payload_arity
  if member.fields.len > 0:
    return member.fields.len
  member.field_type_ids.len

proc enum_payload_shape*(member: EnumMember): EnumPayloadShapeKind {.inline.} =
  if member == nil:
    return EpsUnit
  let arity = enum_payload_arity(member)
  if arity == 0:
    return EpsUnit
  if member.payload_shape != EpsUnit:
    return member.payload_shape
  if member.fields.len > 0:
    return EpsNamed
  EpsPositional

proc enum_payload_slot_label*(member: EnumMember, index: int): string =
  if member != nil and enum_payload_shape(member) == EpsNamed and index >= 0 and index < member.fields.len:
    return member.fields[index]
  "#" & $index

proc new_enum_member*(parent: Value, name: string, value: int,
                      fields: seq[string] = @[],
                      field_type_ids: seq[TypeId] = @[],
                      field_type_descs: seq[TypeDesc] = @[],
                      payload_shape: EnumPayloadShapeKind = EpsUnit,
                      payload_arity: int = -1): EnumMember =
  let inferred = infer_enum_payload_shape(fields, field_type_ids, payload_shape, payload_arity)
  return EnumMember(
    parent: parent,
    name: name,
    value: value,
    payload_shape: inferred.shape,
    payload_arity: inferred.arity,
    fields: fields,
    field_type_ids: field_type_ids,
    field_type_descs: copy_enum_type_descs(field_type_descs),
  )

proc to_value*(e: EnumDef): Value =
  let r = new_ref(VkEnum)
  r.enum_def = e
  return r.to_ref_value()

proc to_value*(m: EnumMember): Value =
  let r = new_ref(VkEnumMember)
  r.enum_member = m
  return r.to_ref_value()

proc add_member*(self: Value, name: string, value: int, fields: seq[string] = @[],
                 field_type_ids: seq[TypeId] = @[],
                 field_type_descs: seq[TypeDesc] = @[],
                 payload_shape: EnumPayloadShapeKind = EpsUnit,
                 payload_arity: int = -1) =
  if self.kind != VkEnum:
    not_allowed("add_member can only be called on enums")
  let inferred = infer_enum_payload_shape(fields, field_type_ids, payload_shape, payload_arity)
  if inferred.shape == EpsNamed and fields.len != inferred.arity:
    not_allowed("enum member " & name & " named payload metadata count " & $fields.len &
                " does not match payload arity " & $inferred.arity)
  if inferred.shape == EpsPositional and fields.len != 0:
    not_allowed("enum member " & name & " positional payload metadata must not contain field names")
  if inferred.shape == EpsUnit and (fields.len != 0 or inferred.arity != 0):
    not_allowed("enum member " & name & " unit payload metadata must be empty")

  var member_type_ids = field_type_ids
  if member_type_ids.len == 0 and inferred.arity > 0:
    member_type_ids = newSeq[TypeId](inferred.arity)
    for i in 0..<member_type_ids.len:
      member_type_ids[i] = NO_TYPE_ID
  if member_type_ids.len != inferred.arity:
    not_allowed("enum member " & name & " field type metadata count " & $member_type_ids.len &
                " does not match payload arity " & $inferred.arity)
  let descs =
    if field_type_descs.len > 0:
      field_type_descs
    else:
      self.ref.enum_def.field_type_descs
  let member = new_enum_member(self, name, value, fields, member_type_ids, descs,
    inferred.shape, inferred.arity)
  self.ref.enum_def.members[name] = member

proc new_enum_value*(variant: Value, data: seq[Value]): Value =
  let r = new_ref(VkEnumValue)
  r.ev_variant = variant
  r.ev_data = data
  return r.to_ref_value()

proc qualified_enum_member_name*(member: EnumMember): string =
  if member == nil:
    return "<nil>"
  let parent = member.parent
  let enum_name =
    if parent.kind == VkEnum and parent.ref.enum_def != nil and parent.ref.enum_def.name.len > 0:
      parent.ref.enum_def.name
    else:
      "<enum>"
  enum_name & "/" & member.name

proc validate_enum_payload_arity*(member: EnumMember, actual: int, context = "EnumValue") =
  if member == nil:
    not_allowed(context & " requires an enum member")
  let expected = enum_payload_arity(member)
  if actual != expected:
    let field_names = if expected > 0 and enum_payload_shape(member) == EpsNamed: " (" & member.fields.join(", ") & ")" else: ""
    not_allowed(context & " " & qualified_enum_member_name(member) &
                " expects " & $expected & " payload value(s)" & field_names &
                ", got " & $actual)

proc `[]`*(self: Value, name: string): Value =
  if self.kind != VkEnum:
    not_allowed("enum member access can only be used on enums")
  if name in self.ref.enum_def.members:
    return self.ref.enum_def.members[name].to_value()
  else:
    not_allowed("enum " & self.ref.enum_def.name & " has no member " & name)