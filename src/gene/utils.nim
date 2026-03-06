import strutils

# "0123456789".abbrev(6) => "012...789"
# "0123456789".abbrev(20) => "0123456789"
proc abbrev*(s: string, len: int): string =
  if len >= s.len:
    return s
  else:
    s[0..int((len+1)/2)] & "..." & s[s.len - int(len/2)..^1]

proc to_int*(x: string): (bool, int) =
  try:
    result = (true, parse_int(x))
  except ValueError:
    result = (false, 0)

proc is_generic_type_param_name*(name: string): bool =
  if name.len == 0:
    return false
  if name[0] notin {'A'..'Z'}:
    return false
  for ch in name:
    if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
      return false
  true

proc split_generic_definition_name*(name: string): tuple[base_name: string, type_params: seq[string]] =
  result = (name, @[])
  if name.len == 0:
    return
  let parts = name.split(':')
  if parts.len < 2 or parts[0].len == 0:
    return
  for i in 1..<parts.len:
    if not is_generic_type_param_name(parts[i]):
      return
  result.base_name = parts[0]
  result.type_params = parts[1..^1]
