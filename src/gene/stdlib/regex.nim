import re, tables

import ../types
import ../text_utils

type RegexCacheKey = tuple[pattern: string, flags: uint8]
type RegexCaptureInfo = object
  names: seq[string]

var regex_cache {.threadvar.}: Table[RegexCacheKey, Regex]
var regex_cache_initialized {.threadvar.}: bool

proc build_regex_flags(ignore_case: bool, multiline: bool): uint8 {.inline, gcsafe.} =
  result = 0
  if ignore_case:
    result = result or REGEX_FLAG_IGNORE_CASE
  if multiline:
    result = result or REGEX_FLAG_MULTILINE

proc get_compiled_regex(pattern: string, flags: uint8): Regex {.gcsafe.} =
  if not regex_cache_initialized:
    regex_cache = init_table[RegexCacheKey, Regex]()
    regex_cache_initialized = true
  let key = (pattern, flags)
  if not regex_cache.hasKey(key):
    var opts: set[RegexFlag] = {}
    if (flags and REGEX_FLAG_IGNORE_CASE) != 0:
      opts.incl(reIgnoreCase)
    if (flags and REGEX_FLAG_MULTILINE) != 0:
      opts.incl(reDotAll)
    regex_cache[key] = re(pattern, opts)
  regex_cache[key]

proc extract_regex(value: Value, pattern: var string, flags: var uint8) {.gcsafe.} =
  case value.kind
  of VkRegex:
    pattern = value.ref.regex_pattern
    flags = value.ref.regex_flags
  of VkString:
    pattern = value.str
    flags = 0
  else:
    not_allowed("Expected a regex or string pattern")

proc analyze_regex_captures(pattern: string): RegexCaptureInfo {.gcsafe.} =
  var escaped = false
  var in_class = false
  var i = 0
  while i < pattern.len:
    let ch = pattern[i]
    if escaped:
      escaped = false
      inc i
      continue
    if ch == '\\':
      escaped = true
      inc i
      continue
    if in_class:
      if ch == ']':
        in_class = false
      inc i
      continue
    if ch == '[':
      in_class = true
      inc i
      continue
    if ch == '(':
      if result.names.len >= MaxSubpatterns:
        inc i
        continue
      if i + 1 < pattern.len and pattern[i + 1] == '?':
        if i + 2 < pattern.len and pattern[i + 2] == '<':
          if i + 3 < pattern.len and pattern[i + 3] notin {'=', '!'}:
            var j = i + 3
            while j < pattern.len and pattern[j] != '>':
              j.inc()
            result.names.add(if j < pattern.len: pattern[i + 3 ..< j] else: "")
            i = if j < pattern.len: j else: i
        elif i + 2 < pattern.len and pattern[i + 2] == '\'':
          var j = i + 3
          while j < pattern.len and pattern[j] != '\'':
            j.inc()
          result.names.add(if j < pattern.len: pattern[i + 3 ..< j] else: "")
          i = if j < pattern.len: j else: i
        elif i + 3 < pattern.len and pattern[i + 2] == 'P' and pattern[i + 3] == '<':
          var j = i + 4
          while j < pattern.len and pattern[j] != '>':
            j.inc()
          result.names.add(if j < pattern.len: pattern[i + 4 ..< j] else: "")
          i = if j < pattern.len: j else: i
      else:
        result.names.add("")
    inc i

proc regex_capture_count(info: RegexCaptureInfo): int {.inline, gcsafe.} =
  info.names.len

proc build_named_capture_values(info: RegexCaptureInfo, captures: seq[string]): Table[Key, Value] {.gcsafe.} =
  result = initTable[Key, Value]()
  for i, name in info.names:
    if name.len > 0 and i < captures.len:
      result[name.to_key()] = captures[i].to_value()

proc build_named_capture_strings(info: RegexCaptureInfo, captures: seq[string]): Table[string, string] {.gcsafe.} =
  result = initTable[string, string]()
  for i, name in info.names:
    if name.len > 0 and i < captures.len:
      result[name] = captures[i]

proc apply_regex_replacement(replacement_str: string, captures: seq[string],
                             named_captures: Table[string, string], full_match: string): string {.gcsafe.} =
  result = ""
  var i = 0
  while i < replacement_str.len:
    if replacement_str[i] == '\\' and i + 1 < replacement_str.len:
      let next = replacement_str[i + 1]
      if next == '\\':
        result.add('\\')
        i += 2
        continue
      if next in {'0'..'9'}:
        var j = i + 1
        var num = 0
        while j < replacement_str.len and replacement_str[j] in {'0'..'9'}:
          num = num * 10 + (ord(replacement_str[j]) - ord('0'))
          j.inc()
        if num == 0:
          result.add(full_match)
        elif num - 1 < captures.len:
          result.add(captures[num - 1])
        i = j
        continue
      if next in {'k', 'g'} and i + 2 < replacement_str.len and replacement_str[i + 2] in {'<', '\''}:
        let close_delim = if replacement_str[i + 2] == '<': '>' else: '\''
        var j = i + 3
        while j < replacement_str.len and replacement_str[j] != close_delim:
          j.inc()
        if j < replacement_str.len:
          let name = replacement_str[i + 3 ..< j]
          if named_captures.hasKey(name):
            result.add(named_captures[name])
          i = j + 1
          continue
      result.add('\\')
      i.inc()
      continue
    result.add(replacement_str[i])
    i.inc()

proc regex_find_bounds(input: string, regex_val: Value,
                       capture_info: RegexCaptureInfo,
                       captures: var seq[string],
                       start = 0): tuple[first, last: int] {.gcsafe.} =
  let regex_obj = get_compiled_regex(regex_val.ref.regex_pattern, regex_val.ref.regex_flags)
  captures = newSeq[string](regex_capture_count(capture_info))
  re.findBounds(input, regex_obj, captures, start)

proc regex_find_byte_bounds*(input: string, regex_val: Value,
                             start = 0): tuple[first, last: int] {.gcsafe.} =
  if regex_val.kind != VkRegex:
    not_allowed("Expected a Regexp")
  let capture_info = analyze_regex_captures(regex_val.ref.regex_pattern)
  var captures: seq[string]
  regex_find_bounds(input, regex_val, capture_info, captures, start)

proc build_regex_match_value(input: string, capture_info: RegexCaptureInfo,
                             captures: seq[string], first: int, last: int): Value {.gcsafe.} =
  let end_pos = if last >= first: last + 1 else: first
  let match_val = if last >= first: input[first .. last] else: ""
  let pre_match = if first > 0: input[0 ..< first] else: ""
  let post_match = if end_pos < input.len: input[end_pos .. ^1] else: ""
  let named_captures = build_named_capture_values(capture_info, captures)
  let char_start = utf8_char_pos_for_byte_offset(input, first)
  let char_end = utf8_char_pos_for_byte_offset(input, end_pos)
  new_regex_match_value(match_val, captures, named_captures, char_start.int64,
                        char_end.int64, pre_match, post_match)

proc regex_match_bool*(input: string, regex_val: Value): bool {.gcsafe.} =
  if regex_val.kind != VkRegex:
    not_allowed("Expected a Regexp")
  let regex_obj = get_compiled_regex(regex_val.ref.regex_pattern, regex_val.ref.regex_flags)
  return re.find(input, regex_obj) >= 0

proc regex_process_match*(input: string, regex_val: Value): Value {.gcsafe.} =
  if regex_val.kind != VkRegex:
    not_allowed("Expected a Regexp")
  let capture_info = analyze_regex_captures(regex_val.ref.regex_pattern)
  var captures: seq[string]
  let (first, last) = regex_find_bounds(input, regex_val, capture_info, captures)
  if first < 0:
    return NIL
  build_regex_match_value(input, capture_info, captures, first, last)

proc regex_find_first*(input: string, regex_val: Value): Value {.gcsafe.} =
  if regex_val.kind != VkRegex:
    not_allowed("Expected a Regexp")
  let capture_info = analyze_regex_captures(regex_val.ref.regex_pattern)
  var captures: seq[string]
  let (first, last) = regex_find_bounds(input, regex_val, capture_info, captures)
  if first < 0:
    return NIL
  if last < first:
    return "".to_value()
  input[first .. last].to_value()

proc regex_find_all_values*(input: string, regex_val: Value): Value {.gcsafe.} =
  if regex_val.kind != VkRegex:
    not_allowed("Expected a Regexp")
  let pattern = regex_val.ref.regex_pattern
  let flags = regex_val.ref.regex_flags
  let regex_obj = get_compiled_regex(pattern, flags)
  var matches = new_array_value()
  for match in re.findAll(input, regex_obj):
    array_data(matches).add(match.to_value())
  matches

proc regex_replacement_from_args(regex_val: Value, replacement_override: Value): string {.gcsafe.} =
  if replacement_override.kind == VkString:
    return replacement_override.str
  if replacement_override != NIL and replacement_override != VOID:
    not_allowed("Replacement must be a string")
  if regex_val.ref.regex_has_replacement:
    return regex_val.ref.regex_replacement
  not_allowed("Replacement string is required")
  ""

proc regex_replace_internal(input: string, regex_obj: Regex, replacement: string,
                            capture_info: RegexCaptureInfo, replace_all: bool): string =
  var result_str = ""
  var search_pos = 0
  var captures = newSeq[string](regex_capture_count(capture_info))
  let named_capture_count = regex_capture_count(capture_info)
  while search_pos <= input.len:
    if captures.len > 0:
      for i in 0..<captures.len:
        captures[i] = ""
    let (first, last) = re.findBounds(input, regex_obj, captures, search_pos)
    if first < 0:
      break
    if first > search_pos:
      result_str.add(input[search_pos ..< first])
    let match_val = if last >= first: input[first .. last] else: ""
    let named_captures =
      if named_capture_count > 0: build_named_capture_strings(capture_info, captures)
      else: initTable[string, string]()
    result_str.add(apply_regex_replacement(replacement, captures, named_captures, match_val))
    let next_pos = if last >= first: last + 1 else: first
    if not replace_all:
      if next_pos < input.len:
        result_str.add(input[next_pos .. ^1])
      return result_str
    if next_pos == search_pos:
      if search_pos < input.len:
        result_str.add(input[search_pos])
      search_pos = next_pos + 1
    else:
      search_pos = next_pos
  if search_pos < input.len:
    result_str.add(input[search_pos .. ^1])
  result_str

proc regex_replace_value*(input: string, regex_val: Value,
                          replacement_override: Value, replace_all: bool): Value {.gcsafe.} =
  if regex_val.kind != VkRegex:
    not_allowed("Expected a Regexp")
  let pattern = regex_val.ref.regex_pattern
  let flags = regex_val.ref.regex_flags
  let replacement = regex_replacement_from_args(regex_val, replacement_override)
  let regex_obj = get_compiled_regex(pattern, flags)
  let capture_info = analyze_regex_captures(pattern)
  regex_replace_internal(input, regex_obj, replacement, capture_info, replace_all).to_value()

proc regex_split_values*(input: string, regex_val: Value, limit = 0): Value {.gcsafe.} =
  if regex_val.kind != VkRegex:
    not_allowed("Expected a Regexp")
  let regex_obj = get_compiled_regex(regex_val.ref.regex_pattern, regex_val.ref.regex_flags)
  let maxsplit = if limit > 0: limit - 1 else: -1
  var matches = new_array_value()
  for part in re.split(input, regex_obj, maxsplit):
    array_data(matches).add(part.to_value())
  matches

proc init_regex_class*(object_class: Class) =
  var r: ptr Reference
  let regex_class = new_class("Regexp")
  regex_class.parent = object_class

  proc regexp_constructor(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let pos_count = get_positional_count(arg_count, has_keyword_args)
    if pos_count < 1:
      not_allowed("Regexp.ctor requires a pattern string")
    let pattern_val = get_positional_arg(args, 0, has_keyword_args)
    if pattern_val.kind != VkString:
      not_allowed("Regexp.ctor expects a string pattern")

    var replacement = ""
    var has_replacement = false
    if pos_count >= 2:
      let replacement_val = get_positional_arg(args, 1, has_keyword_args)
      if replacement_val != NIL and replacement_val.kind != VkString:
        not_allowed("Regexp.ctor replacement must be a string or nil")
      if replacement_val.kind == VkString:
        replacement = replacement_val.str
        has_replacement = true
    if pos_count > 2:
      not_allowed("Regexp.ctor accepts at most pattern and replacement")

    var ignore_case = false
    var multiline = false
    if has_keyword_args and args[0].kind == VkMap:
      for k, v in map_data(args[0]):
        let key_name = cast[Value](k).str
        case key_name
        of "i":
          ignore_case = v.to_bool()
        of "m":
          multiline = v.to_bool()
        else:
          not_allowed("Regexp.ctor unknown flag: " & key_name)

    let flags = build_regex_flags(ignore_case, multiline)
    new_regex_value(pattern_val.str, flags, replacement, has_replacement)

  regex_class.def_native_constructor(regexp_constructor)

  proc regexp_match(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Regexp.match requires an input string")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    let input_val = get_positional_arg(args, 1, has_keyword_args)
    if self_arg.kind != VkRegex or input_val.kind != VkString:
      not_allowed("Regexp.match expects a Regexp and string")
    regex_process_match(input_val.str, self_arg)

  proc regexp_match_predicate(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Regexp.match? requires an input string")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    let input_val = get_positional_arg(args, 1, has_keyword_args)
    if self_arg.kind != VkRegex or input_val.kind != VkString:
      not_allowed("Regexp.match? expects a Regexp and string")
    regex_match_bool(input_val.str, self_arg).to_value()

  proc regexp_process(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Regexp.process requires an input string")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    let input_val = get_positional_arg(args, 1, has_keyword_args)
    if self_arg.kind != VkRegex or input_val.kind != VkString:
      not_allowed("Regexp.process expects a Regexp and string")
    regex_process_match(input_val.str, self_arg)

  proc regexp_find(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Regexp.find requires an input string")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    let input_val = get_positional_arg(args, 1, has_keyword_args)
    if self_arg.kind != VkRegex or input_val.kind != VkString:
      not_allowed("Regexp.find expects a Regexp and string")
    regex_find_first(input_val.str, self_arg)

  proc regexp_find_all(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    if get_positional_count(arg_count, has_keyword_args) < 2:
      not_allowed("Regexp.find_all requires an input string")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    let input_val = get_positional_arg(args, 1, has_keyword_args)
    if self_arg.kind != VkRegex or input_val.kind != VkString:
      not_allowed("Regexp.find_all expects a Regexp and string")
    regex_find_all_values(input_val.str, self_arg)

  proc regexp_split(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let pos_count = get_positional_count(arg_count, has_keyword_args)
    if pos_count < 2:
      not_allowed("Regexp.split requires an input string")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    let input_val = get_positional_arg(args, 1, has_keyword_args)
    if self_arg.kind != VkRegex or input_val.kind != VkString:
      not_allowed("Regexp.split expects a Regexp and string")
    let limit = if pos_count >= 3: max(1, get_positional_arg(args, 2, has_keyword_args).to_int().int) else: 0
    regex_split_values(input_val.str, self_arg, limit)

  proc regexp_scan(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    regexp_find_all(vm, args, arg_count, has_keyword_args)

  proc regexp_replace(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let pos_count = get_positional_count(arg_count, has_keyword_args)
    if pos_count < 2:
      not_allowed("Regexp.replace requires an input string")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    let input_val = get_positional_arg(args, 1, has_keyword_args)
    if self_arg.kind != VkRegex or input_val.kind != VkString:
      not_allowed("Regexp.replace expects a Regexp and string")
    let replacement_val = if pos_count >= 3: get_positional_arg(args, 2, has_keyword_args) else: NIL
    regex_replace_value(input_val.str, self_arg, replacement_val, false)

  proc regexp_replace_all(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let pos_count = get_positional_count(arg_count, has_keyword_args)
    if pos_count < 2:
      not_allowed("Regexp.replace_all requires an input string")
    let self_arg = get_positional_arg(args, 0, has_keyword_args)
    let input_val = get_positional_arg(args, 1, has_keyword_args)
    if self_arg.kind != VkRegex or input_val.kind != VkString:
      not_allowed("Regexp.replace_all expects a Regexp and string")
    let replacement_val = if pos_count >= 3: get_positional_arg(args, 2, has_keyword_args) else: NIL
    regex_replace_value(input_val.str, self_arg, replacement_val, true)

  proc regexp_sub(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    regexp_replace(vm, args, arg_count, has_keyword_args)

  proc regexp_gsub(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    regexp_replace_all(vm, args, arg_count, has_keyword_args)

  regex_class.def_native_method("match", regexp_match)
  regex_class.def_native_method("match?", regexp_match_predicate)
  regex_class.def_native_method("process", regexp_process)
  regex_class.def_native_method("find", regexp_find)
  regex_class.def_native_method("find_all", regexp_find_all)
  regex_class.def_native_method("split", regexp_split)
  regex_class.def_native_method("scan", regexp_scan)
  regex_class.def_native_method("replace", regexp_replace)
  regex_class.def_native_method("replace_all", regexp_replace_all)
  regex_class.def_native_method("sub", regexp_sub)
  regex_class.def_native_method("gsub", regexp_gsub)

  r = new_ref(VkClass)
  r.class = regex_class
  App.app.regex_class = r.to_ref_value()
  App.app.gene_ns.ns["Regexp".to_key()] = App.app.regex_class
  App.app.global_ns.ns["Regexp".to_key()] = App.app.regex_class
