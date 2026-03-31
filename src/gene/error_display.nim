import std/algorithm
import std/json as nim_json
import std/strutils

import ./vm/diagnostics

const
  DIAGNOSTIC_FIELD_ORDER = ["message", "code", "severity", "stage", "span", "hints", "repair_tags"]
  DIAGNOSTIC_SPAN_ORDER = ["file", "line", "column"]

proc render_json_node(node: nim_json.JsonNode): string

proc render_json_object(node: nim_json.JsonNode; preferred_order: openArray[string] = []): string =
  var keys: seq[string] = @[]
  for key in preferred_order:
    if node.hasKey(key):
      keys.add(key)

  var extras: seq[string] = @[]
  for key, _ in node:
    var is_preferred = false
    for preferred in preferred_order:
      if key == preferred:
        is_preferred = true
        break
    if not is_preferred:
      extras.add(key)
  extras.sort(system.cmp[string])
  keys.add(extras)

  result = "{"
  for i, key in keys:
    if i > 0:
      result &= " "
    result &= "^" & key & " "
    if key == "span" and node[key].kind == nim_json.JObject:
      result &= render_json_object(node[key], DIAGNOSTIC_SPAN_ORDER)
    else:
      result &= render_json_node(node[key])
  result &= "}"

proc render_json_node(node: nim_json.JsonNode): string =
  case node.kind
  of nim_json.JNull:
    "nil"
  of nim_json.JBool:
    if node.bval: "true" else: "false"
  of nim_json.JInt:
    $int64(node.num)
  of nim_json.JFloat:
    $node.fnum
  of nim_json.JString:
    nim_json.escapeJson(node.str)
  of nim_json.JArray:
    var items: seq[string] = @[]
    for item in node.elems:
      items.add(render_json_node(item))
    "[" & items.join(" ") & "]"
  of nim_json.JObject:
    render_json_object(node)

proc render_diagnostic_message(message: string): string =
  let parsed = nim_json.parseJson(message)
  if parsed.kind != nim_json.JObject or not parsed.hasKey("code") or not parsed.hasKey("message"):
    return message
  render_json_object(parsed, DIAGNOSTIC_FIELD_ORDER)

proc render_error_message*(message: string): string =
  if not is_diagnostic_envelope(message):
    return message

  try:
    return render_diagnostic_message(message)
  except CatchableError:
    return message
