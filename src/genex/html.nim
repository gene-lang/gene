import tables, strutils
import ../gene/types

# Helper to create native function value
proc wrap_native_fn(fn: NativeFn): Value =
  let r = new_ref(VkNativeFn)
  r.native_fn = fn
  return r.to_ref_value()

# Helper to convert props to HTML attributes
proc props_to_attrs(props: Table[Key, Value]): string =
  var attrs: seq[string] = @[]
  for k, v in props:
    let key_val = cast[Value](k)
    let key_str = if key_val.kind == VkSymbol:
      key_val.str
    else:
      continue

    # Skip special keys that start with _
    if key_str.startsWith("_"):
      continue

    let val_str = case v.kind:
      of VkString: v.str
      of VkInt: $v.to_int
      of VkBool: $v.to_bool
      of VkMap:
        # Handle style maps like {^font-size "12px"}
        var style_parts: seq[string] = @[]
        for sk, sv in map_data(v):
          let style_key = cast[Value](sk)
          if style_key.kind == VkSymbol:
            let style_val = if sv.kind == VkString: sv.str else: $sv
            style_parts.add(style_key.str & ": " & style_val)
        style_parts.join("; ")
      else: $v

    attrs.add(key_str & "=\"" & val_str.replace("\"", "&quot;") & "\"")

  if attrs.len > 0:
    return " " & attrs.join(" ")
  else:
    return ""

# Generic HTML tag function
proc html_tag(tag_name: string, vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  var attrs = ""
  var content = ""

  # Check for keyword args (props)
  if has_keyword_args and arg_count > 0:
    let props_arg = args[arg_count - 1]
    if props_arg.kind == VkMap:
      attrs = props_to_attrs(map_data(props_arg))
      # Content comes from positional args before the props
      for i in 0..<(arg_count - 1):
        let arg = get_positional_arg(args, i, has_keyword_args)
        if arg.kind == VkString:
          content &= arg.str
        else:
          content &= $arg
    else:
      # All args are content
      for i in 0..<arg_count:
        let arg = get_positional_arg(args, i, has_keyword_args)
        if arg.kind == VkString:
          content &= arg.str
        else:
          content &= $arg
  else:
    # All args are content
    for i in 0..<arg_count:
      let arg = get_positional_arg(args, i, has_keyword_args)
      if arg.kind == VkString:
        content &= arg.str
      else:
        content &= $arg

  let html = "<" & tag_name & attrs & ">" & content & "</" & tag_name & ">"
  return new_str_value(html)

# Self-closing tag helper
proc html_self_closing_tag(tag_name: string, vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  var attrs = ""

  # Check for keyword args (props)
  if has_keyword_args and arg_count > 0:
    let props_arg = args[arg_count - 1]
    if props_arg.kind == VkMap:
      attrs = props_to_attrs(map_data(props_arg))

  let html = "<" & tag_name & attrs & " />"
  return new_str_value(html)

# Define all HTML tag functions
proc tag_HTML(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("html", vm, args, arg_count, has_keyword_args)
proc tag_HEAD(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("head", vm, args, arg_count, has_keyword_args)
proc tag_TITLE(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("title", vm, args, arg_count, has_keyword_args)
proc tag_BODY(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("body", vm, args, arg_count, has_keyword_args)
proc tag_DIV(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("div", vm, args, arg_count, has_keyword_args)
proc tag_SPAN(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("span", vm, args, arg_count, has_keyword_args)
proc tag_P(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("p", vm, args, arg_count, has_keyword_args)
proc tag_H1(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("h1", vm, args, arg_count, has_keyword_args)
proc tag_H2(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("h2", vm, args, arg_count, has_keyword_args)
proc tag_H3(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("h3", vm, args, arg_count, has_keyword_args)
proc tag_UL(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("ul", vm, args, arg_count, has_keyword_args)
proc tag_OL(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("ol", vm, args, arg_count, has_keyword_args)
proc tag_LI(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("li", vm, args, arg_count, has_keyword_args)
proc tag_FORM(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("form", vm, args, arg_count, has_keyword_args)
proc tag_INPUT(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_self_closing_tag("input", vm, args, arg_count, has_keyword_args)
proc tag_BUTTON(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("button", vm, args, arg_count, has_keyword_args)
proc tag_LABEL(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("label", vm, args, arg_count, has_keyword_args)
proc tag_A(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("a", vm, args, arg_count, has_keyword_args)
proc tag_IMG(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_self_closing_tag("img", vm, args, arg_count, has_keyword_args)
proc tag_TABLE(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("table", vm, args, arg_count, has_keyword_args)
proc tag_TR(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("tr", vm, args, arg_count, has_keyword_args)
proc tag_TD(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("td", vm, args, arg_count, has_keyword_args)
proc tag_TH(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("th", vm, args, arg_count, has_keyword_args)
proc tag_HEADER(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("header", vm, args, arg_count, has_keyword_args)
proc tag_FOOTER(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("footer", vm, args, arg_count, has_keyword_args)
proc tag_SCRIPT(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("script", vm, args, arg_count, has_keyword_args)
proc tag_STYLE(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("style", vm, args, arg_count, has_keyword_args)
proc tag_LINK(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_self_closing_tag("link", vm, args, arg_count, has_keyword_args)
proc tag_META(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_self_closing_tag("meta", vm, args, arg_count, has_keyword_args)
proc tag_SVG(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("svg", vm, args, arg_count, has_keyword_args)
proc tag_LINE(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_self_closing_tag("line", vm, args, arg_count, has_keyword_args)

# Register functions in namespace
proc init_html_module*() =
  VmCreatedCallbacks.add proc() =
    {.cast(gcsafe).}:
      # Ensure App is initialized
      if App == NIL or App.kind != VkApplication:
        return

      if App.app.genex_ns == NIL:
        return

      var html_ns = new_namespace("html")

      # Create tags namespace for wildcard import
      var tags_ns = new_namespace("tags")

      # Register all tag functions in tags namespace
      tags_ns["HTML".to_key()] = wrap_native_fn(tag_HTML)
      tags_ns["HEAD".to_key()] = wrap_native_fn(tag_HEAD)
      tags_ns["TITLE".to_key()] = wrap_native_fn(tag_TITLE)
      tags_ns["BODY".to_key()] = wrap_native_fn(tag_BODY)
      tags_ns["DIV".to_key()] = wrap_native_fn(tag_DIV)
      tags_ns["SPAN".to_key()] = wrap_native_fn(tag_SPAN)
      tags_ns["P".to_key()] = wrap_native_fn(tag_P)
      tags_ns["H1".to_key()] = wrap_native_fn(tag_H1)
      tags_ns["H2".to_key()] = wrap_native_fn(tag_H2)
      tags_ns["H3".to_key()] = wrap_native_fn(tag_H3)
      tags_ns["UL".to_key()] = wrap_native_fn(tag_UL)
      tags_ns["OL".to_key()] = wrap_native_fn(tag_OL)
      tags_ns["LI".to_key()] = wrap_native_fn(tag_LI)
      tags_ns["FORM".to_key()] = wrap_native_fn(tag_FORM)
      tags_ns["INPUT".to_key()] = wrap_native_fn(tag_INPUT)
      tags_ns["BUTTON".to_key()] = wrap_native_fn(tag_BUTTON)
      tags_ns["LABEL".to_key()] = wrap_native_fn(tag_LABEL)
      tags_ns["A".to_key()] = wrap_native_fn(tag_A)
      tags_ns["IMG".to_key()] = wrap_native_fn(tag_IMG)
      tags_ns["TABLE".to_key()] = wrap_native_fn(tag_TABLE)
      tags_ns["TR".to_key()] = wrap_native_fn(tag_TR)
      tags_ns["TD".to_key()] = wrap_native_fn(tag_TD)
      tags_ns["TH".to_key()] = wrap_native_fn(tag_TH)
      tags_ns["HEADER".to_key()] = wrap_native_fn(tag_HEADER)
      tags_ns["FOOTER".to_key()] = wrap_native_fn(tag_FOOTER)
      tags_ns["SCRIPT".to_key()] = wrap_native_fn(tag_SCRIPT)
      tags_ns["STYLE".to_key()] = wrap_native_fn(tag_STYLE)
      tags_ns["LINK".to_key()] = wrap_native_fn(tag_LINK)
      tags_ns["META".to_key()] = wrap_native_fn(tag_META)
      tags_ns["SVG".to_key()] = wrap_native_fn(tag_SVG)
      tags_ns["LINE".to_key()] = wrap_native_fn(tag_LINE)

      # Register tags namespace
      html_ns["tags".to_key()] = tags_ns.to_value()

      # Register html namespace under genex
      App.app.genex_ns.ref.ns["html".to_key()] = html_ns.to_value()

# Auto-initialize on import
init_html_module()
