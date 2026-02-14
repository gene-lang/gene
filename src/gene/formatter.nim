import algorithm, strutils, tables

import ./types
import ./parser

const
  INDENT_SIZE* = 2
  DEFAULT_MAX_WIDTH* = 100

type
  CommentBlock* = object
    start_line*: int
    end_line*: int
    text*: string

proc normalize_newlines*(source: string): string =
  source.replace("\r\n", "\n").replace('\r', '\n')

proc indent_str(level: int): string =
  " ".repeat(level * INDENT_SIZE)

proc escape_char_literal(ch: char): string =
  case ch
  of '\n': "'\\n'"
  of '\r': "'\\r'"
  of '\t': "'\\t'"
  of '\b': "'\\b'"
  of '\f': "'\\f'"
  of '\\': "'\\\\'"
  of '\'': "'\\\''"
  else: "'" & $ch & "'"

proc escape_string_literal(text: string): string =
  result = "\""
  for ch in text:
    case ch
    of '"': result &= "\\\""
    of '\\': result &= "\\\\"
    of '\n': result &= "\\n"
    of '\r': result &= "\\r"
    of '\t': result &= "\\t"
    of '\b': result &= "\\b"
    of '\f': result &= "\\f"
    else: result.add(ch)
  result &= "\""

proc escape_regex_segment(segment: string): string =
  result = ""
  for ch in segment:
    case ch
    of '\\': result &= "\\\\"
    of '/': result &= "\\/"
    else: result.add(ch)

proc regex_flags_to_string(flags: uint8): string =
  result = ""
  if (flags and REGEX_FLAG_IGNORE_CASE) != 0:
    result.add('i')
  if (flags and REGEX_FLAG_MULTILINE) != 0:
    result.add('m')

proc format_regex_literal(value: Value): string =
  result = "#/" & escape_regex_segment(value.ref.regex_pattern) & "/"
  if value.ref.regex_has_replacement:
    result &= escape_regex_segment(value.ref.regex_replacement) & "/"
  result &= regex_flags_to_string(value.ref.regex_flags)

proc key_to_name(key: Key): string =
  get_symbol(symbol_index(key))

proc strip_trailing_newlines(text: string): string =
  result = text
  while result.len > 0 and (result[^1] == '\n' or result[^1] == '\r'):
    result.setLen(result.len - 1)

proc extract_comments*(source: string): seq[CommentBlock] =
  let normalized = normalize_newlines(source)
  var i = 0
  var line = 1
  var in_string = false
  var in_char = false

  template advance_one() =
    if normalized[i] == '\n':
      inc line
    inc i

  while i < normalized.len:
    if in_string:
      if normalized[i] == '\\' and i + 1 < normalized.len:
        advance_one()
        advance_one()
      elif normalized[i] == '"':
        in_string = false
        advance_one()
      else:
        advance_one()
      continue

    if in_char:
      if normalized[i] == '\\' and i + 1 < normalized.len:
        advance_one()
        advance_one()
      elif normalized[i] == '\'':
        in_char = false
        advance_one()
      else:
        advance_one()
      continue

    case normalized[i]
    of '"':
      in_string = true
      advance_one()
    of '\'':
      in_char = true
      advance_one()
    of '#':
      let next = if i + 1 < normalized.len: normalized[i + 1] else: '\0'

      if next == '<':
        let start_idx = i
        let start_line = line
        var depth = 1
        advance_one() # '#'
        advance_one() # '<'

        while i < normalized.len and depth > 0:
          if normalized[i] == '#' and i + 1 < normalized.len and normalized[i + 1] == '<':
            inc depth
            advance_one()
            advance_one()
          elif normalized[i] == '>' and i + 1 < normalized.len and normalized[i + 1] == '#':
            dec depth
            advance_one()
            advance_one()
          else:
            advance_one()

        result.add(CommentBlock(
          start_line: start_line,
          end_line: line,
          text: strip_trailing_newlines(normalized[start_idx ..< i]),
        ))
      elif next in {' ', '!', '#', '\t', '\n', '\0'}:
        let start_idx = i
        let start_line = line
        while i < normalized.len and normalized[i] != '\n':
          advance_one()
        result.add(CommentBlock(
          start_line: start_line,
          end_line: start_line,
          text: normalized[start_idx ..< i],
        ))
      else:
        advance_one()
    else:
      advance_one()

proc sorted_prop_entries(props: Table[Key, Value]): seq[(string, Value)] =
  for key, val in props:
    result.add((key_to_name(key), val))
  result.sort(proc(a, b: (string, Value)): int = cmp(a[0], b[0]))

proc sorted_map_entries(map: Table[Key, Value]): seq[(string, Value)] =
  for key, val in map:
    result.add((key_to_name(key), val))
  result.sort(proc(a, b: (string, Value)): int = cmp(a[0], b[0]))

proc render_compact(value: Value): string
proc render_value(value: Value, indent: int, max_width: int): string

proc render_compact(value: Value): string =
  case value.kind
  of VkNil:
    result = "nil"
  of VkVoid:
    result = "void"
  of VkPlaceholder:
    result = "_"
  of VkBool:
    result = if value == TRUE: "true" else: "false"
  of VkInt:
    result = $value.to_int()
  of VkFloat:
    result = $value.to_float()
  of VkChar:
    if value == NOT_FOUND:
      result = "not_found"
    else:
      result = escape_char_literal(chr((value.raw and 0xFF).int))
  of VkString:
    result = escape_string_literal(value.str)
  of VkSymbol:
    result = value.str
  of VkComplexSymbol:
    result = value.ref.csymbol.join("/")
  of VkArray:
    if array_data(value).len == 0:
      return "[]"
    result = "["
    for i, item in array_data(value):
      if i > 0:
        result &= " "
      result &= render_compact(item)
    result &= "]"
  of VkMap:
    let entries = sorted_map_entries(map_data(value))
    if entries.len == 0:
      return "{}"
    result = "{"
    for i, (key, map_val) in entries:
      if i > 0:
        result &= " "
      result &= "^" & key & " " & render_compact(map_val)
    result &= "}"
  of VkGene:
    result = "(" & render_compact(value.gene.`type`)
    for entry in sorted_prop_entries(value.gene.props):
      let key = entry[0]
      let prop_val = entry[1]
      result &= " ^" & key & " " & render_compact(prop_val)
    for child in value.gene.children:
      result &= " " & render_compact(child)
    result &= ")"
  of VkRegex:
    result = format_regex_literal(value)
  else:
    result = $value

proc render_map_entry(key: string, value: Value, indent: int, max_width: int): string =
  let prefix = indent_str(indent) & "^" & key & " "
  let compact = render_compact(value)
  if prefix.len + compact.len <= max_width:
    return prefix & compact

  result = indent_str(indent) & "^" & key
  result &= "\n" & render_value(value, indent + 1, max_width)

proc render_prop_entry(key: string, value: Value, indent: int, max_width: int): string =
  let prefix = indent_str(indent) & "^" & key & " "
  let compact = render_compact(value)
  if prefix.len + compact.len <= max_width:
    return prefix & compact

  result = indent_str(indent) & "^" & key
  result &= "\n" & render_value(value, indent + 1, max_width)

proc render_value(value: Value, indent: int, max_width: int): string =
  let compact = render_compact(value)
  if indent * INDENT_SIZE + compact.len <= max_width:
    return indent_str(indent) & compact

  case value.kind
  of VkArray:
    if array_data(value).len == 0:
      return indent_str(indent) & "[]"
    result = indent_str(indent) & "["
    for item in array_data(value):
      result &= "\n" & render_value(item, indent + 1, max_width)
    result &= "\n" & indent_str(indent) & "]"
  of VkMap:
    let entries = sorted_map_entries(map_data(value))
    if entries.len == 0:
      return indent_str(indent) & "{}"
    result = indent_str(indent) & "{"
    for entry in entries:
      let key = entry[0]
      let map_val = entry[1]
      result &= "\n" & render_map_entry(key, map_val, indent + 1, max_width)
    result &= "\n" & indent_str(indent) & "}"
  of VkGene:
    result = indent_str(indent) & "(" & render_compact(value.gene.`type`)
    let props = sorted_prop_entries(value.gene.props)
    for entry in props:
      let key = entry[0]
      let prop_val = entry[1]
      result &= "\n" & render_prop_entry(key, prop_val, indent + 1, max_width)
    for child in value.gene.children:
      result &= "\n" & render_value(child, indent + 1, max_width)
    result &= "\n" & indent_str(indent) & ")"
  else:
    result = indent_str(indent) & compact

proc parse_forms(source: string, filename: string): seq[Value] =
  var p = new_parser()
  p.open(source, filename)
  defer: p.close()

  while true:
    try:
      let node = p.read()
      if node != PARSER_IGNORE:
        result.add(node)
    except ParseEofError:
      break

proc node_line(value: Value, fallback: int): int =
  if value.kind == VkGene and value.gene != nil and value.gene.trace != nil and value.gene.trace.line > 0:
    return value.gene.trace.line
  fallback

proc render_comment_group(comments: seq[CommentBlock]): string =
  for i, comment in comments:
    if i > 0:
      result &= "\n"
    result &= strip_trailing_newlines(comment.text)

proc render_top_level(forms: seq[Value], comments: seq[CommentBlock], max_width: int): string =
  var positions = newSeq[seq[CommentBlock]](if forms.len > 0: forms.len + 1 else: 1)

  var form_lines: seq[int] = @[]
  var fallback_line = 1
  for form in forms:
    let line = node_line(form, fallback_line)
    form_lines.add(line)
    fallback_line = max(fallback_line + 1, line + 1)

  for comment in comments:
    var pos = 0
    if forms.len > 0:
      pos = forms.len
      for i, form_line in form_lines:
        if comment.start_line < form_line:
          pos = i
          break
    positions[pos].add(comment)

  if forms.len == 0:
    return render_comment_group(positions[0])

  for i, form in forms:
    if i > 0:
      result &= "\n\n"

    if positions[i].len > 0:
      result &= render_comment_group(positions[i])
      result &= "\n"

    result &= render_value(form, 0, max_width)

  if positions[forms.len].len > 0:
    result &= "\n\n"
    result &= render_comment_group(positions[forms.len])

proc format_source*(source: string, filename: string = "<input>", max_width: int = DEFAULT_MAX_WIDTH): string =
  let normalized = normalize_newlines(source)
  let forms = parse_forms(normalized, filename)
  let comments = extract_comments(normalized)
  result = render_top_level(forms, comments, max_width)
  if result.len > 0 and not result.endsWith("\n"):
    result &= "\n"

proc is_canonical_source*(source: string, filename: string = "<input>", max_width: int = DEFAULT_MAX_WIDTH): bool =
  format_source(source, filename, max_width) == normalize_newlines(source)
