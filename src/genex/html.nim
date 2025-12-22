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
proc html_tag(tag_name: string, vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  var attrs = ""
  var content = ""
  let pos_count = get_positional_count(arg_count, has_keyword_args)
  # Keyword args are passed as a map at args[0] when present
  if has_keyword_args and arg_count > 0 and args[0].kind == VkMap:
    attrs = props_to_attrs(map_data(args[0]))

  # All positional args are content
  for i in 0..<pos_count:
    let arg = get_positional_arg(args, i, has_keyword_args)
    if arg.kind == VkString:
      content &= arg.str
    else:
      content &= $arg

  let html = "<" & tag_name & attrs & ">" & content & "</" & tag_name & ">"
  return new_str_value(html)

# Self-closing tag helper
proc html_self_closing_tag(tag_name: string, vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  var attrs = ""

  # Check for keyword args (props)
  if has_keyword_args and arg_count > 0 and args[0].kind == VkMap:
    attrs = props_to_attrs(map_data(args[0]))

  let html = "<" & tag_name & attrs & " />"
  return new_str_value(html)

# Define all HTML tag functions
proc tag_HTML(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("html", vm, args, arg_count, has_keyword_args)
proc tag_HEAD(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("head", vm, args, arg_count, has_keyword_args)
proc tag_TITLE(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("title", vm, args, arg_count, has_keyword_args)
proc tag_BODY(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("body", vm, args, arg_count, has_keyword_args)
proc tag_DIV(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("div", vm, args, arg_count, has_keyword_args)
proc tag_SPAN(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("span", vm, args, arg_count, has_keyword_args)
proc tag_P(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("p", vm, args, arg_count, has_keyword_args)
proc tag_H1(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("h1", vm, args, arg_count, has_keyword_args)
proc tag_H2(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("h2", vm, args, arg_count, has_keyword_args)
proc tag_H3(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("h3", vm, args, arg_count, has_keyword_args)
proc tag_UL(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("ul", vm, args, arg_count, has_keyword_args)
proc tag_OL(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("ol", vm, args, arg_count, has_keyword_args)
proc tag_LI(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("li", vm, args, arg_count, has_keyword_args)
proc tag_FORM(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("form", vm, args, arg_count, has_keyword_args)
proc tag_INPUT(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_self_closing_tag("input", vm, args, arg_count, has_keyword_args)
proc tag_BUTTON(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("button", vm, args, arg_count, has_keyword_args)
proc tag_LABEL(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("label", vm, args, arg_count, has_keyword_args)
proc tag_A(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("a", vm, args, arg_count, has_keyword_args)
proc tag_IMG(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_self_closing_tag("img", vm, args, arg_count, has_keyword_args)
proc tag_TABLE(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("table", vm, args, arg_count, has_keyword_args)
proc tag_TR(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("tr", vm, args, arg_count, has_keyword_args)
proc tag_TD(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("td", vm, args, arg_count, has_keyword_args)
proc tag_TH(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("th", vm, args, arg_count, has_keyword_args)
proc tag_HEADER(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("header", vm, args, arg_count, has_keyword_args)
proc tag_FOOTER(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("footer", vm, args, arg_count, has_keyword_args)
proc tag_SCRIPT(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("script", vm, args, arg_count, has_keyword_args)
proc tag_STYLE(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("style", vm, args, arg_count, has_keyword_args)
proc tag_LINK(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_self_closing_tag("link", vm, args, arg_count, has_keyword_args)
proc tag_META(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_self_closing_tag("meta", vm, args, arg_count, has_keyword_args)
proc tag_SVG(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_tag("svg", vm, args, arg_count, has_keyword_args)
proc tag_LINE(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} = html_self_closing_tag("line", vm, args, arg_count, has_keyword_args)

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

      proc register_tag(name: string, fn: NativeFn) =
        let tag_val = wrap_native_fn(fn)
        tags_ns[name.to_key()] = tag_val
        App.app.global_ns.ref.ns[name.to_key()] = tag_val

      # Register all tag functions in tags namespace
      register_tag("HTML", tag_HTML)
      register_tag("HEAD", tag_HEAD)
      register_tag("TITLE", tag_TITLE)
      register_tag("BODY", tag_BODY)
      register_tag("DIV", tag_DIV)
      register_tag("SPAN", tag_SPAN)
      register_tag("P", tag_P)
      register_tag("H1", tag_H1)
      register_tag("H2", tag_H2)
      register_tag("H3", tag_H3)
      register_tag("UL", tag_UL)
      register_tag("OL", tag_OL)
      register_tag("LI", tag_LI)
      register_tag("FORM", tag_FORM)
      register_tag("INPUT", tag_INPUT)
      register_tag("BUTTON", tag_BUTTON)
      register_tag("LABEL", tag_LABEL)
      register_tag("A", tag_A)
      register_tag("IMG", tag_IMG)
      register_tag("TABLE", tag_TABLE)
      register_tag("TR", tag_TR)
      register_tag("TD", tag_TD)
      register_tag("TH", tag_TH)
      register_tag("HEADER", tag_HEADER)
      register_tag("FOOTER", tag_FOOTER)
      register_tag("SCRIPT", tag_SCRIPT)
      register_tag("STYLE", tag_STYLE)
      register_tag("LINK", tag_LINK)
      register_tag("META", tag_META)
      register_tag("SVG", tag_SVG)
      register_tag("LINE", tag_LINE)

      # Register tags namespace
      html_ns["tags".to_key()] = tags_ns.to_value()

      # Register html namespace under genex
      App.app.genex_ns.ref.ns["html".to_key()] = html_ns.to_value()

# Auto-initialize on import
init_html_module()
