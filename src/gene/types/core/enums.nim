## Enum operations
## Included from core.nim — shares its scope.

proc new_enum*(name: string): EnumDef =
  return EnumDef(
    name: name,
    members: initTable[string, EnumMember]()
  )

proc new_enum_member*(parent: Value, name: string, value: int, fields: seq[string] = @[]): EnumMember =
  return EnumMember(
    parent: parent,
    name: name,
    value: value,
    fields: fields,
  )

proc to_value*(e: EnumDef): Value =
  let r = new_ref(VkEnum)
  r.enum_def = e
  return r.to_ref_value()

proc to_value*(m: EnumMember): Value =
  let r = new_ref(VkEnumMember)
  r.enum_member = m
  return r.to_ref_value()

proc add_member*(self: Value, name: string, value: int, fields: seq[string] = @[]) =
  if self.kind != VkEnum:
    not_allowed("add_member can only be called on enums")
  let member = new_enum_member(self, name, value, fields)
  self.ref.enum_def.members[name] = member

proc new_enum_value*(variant: Value, data: seq[Value]): Value =
  let r = new_ref(VkEnumValue)
  r.ev_variant = variant
  r.ev_data = data
  return r.to_ref_value()

proc `[]`*(self: Value, name: string): Value =
  if self.kind != VkEnum:
    not_allowed("enum member access can only be used on enums")
  if name in self.ref.enum_def.members:
    return self.ref.enum_def.members[name].to_value()
  else:
    not_allowed("enum " & self.ref.enum_def.name & " has no member " & name)