{.push warning[IgnoredSymbolInjection]: off.}
import tables, strutils
import httpclient, uri
import std/json
import asynchttpserver, asyncdispatch
import asyncfutures  # Import asyncfutures explicitly
import nativesockets, net
import cgi

include ../gene/extension/boilerplate
import ../gene/vm
# Explicitly alias to use asyncfutures.Future in this module (preserve generic)
type Future[T] {.used.} = asyncfutures.Future[T]

# Global variables to store classes
var request_class_global: Class
var response_class_global: Class
var server_request_class_global: Class

var server_response_class_global: Class

# Global HTTP server instance
var http_server: AsyncHttpServer
var server_handler: proc(req: Value): Value {.gcsafe.}
var stored_gene_handler: Value  # Store the Gene function/instance
var stored_vm: ptr VirtualMachine   # Store VM reference for execution

# Forward declarations
proc request_constructor(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.}
proc request_send(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.}
proc response_constructor(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.}
proc response_json(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.}
proc vm_start_server(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.}
proc vm_respond(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.}
proc vm_redirect(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.}
proc execute_gene_function(vm: ptr VirtualMachine, fn: Value, args: seq[Value]): Value {.gcsafe.}
proc process_pending_http_requests*(vm: ptr VirtualMachine) {.gcsafe.}

proc parse_json_internal(node: json.JsonNode): Value {.gcsafe.}

proc parse_json*(json_str: string): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    let json_node = json.parseJson(json_str)
    return parse_json_internal(json_node)

proc parse_json_internal(node: json.JsonNode): Value {.gcsafe.} =
  case node.kind:
  of json.JNull:
    return NIL
  of json.JBool:
    return to_value(node.bval)
  of json.JInt:
    return to_value(node.num)
  of json.JFloat:
    return to_value(node.fnum)
  of json.JString:
    return new_str_value(node.str)
  of json.JObject:
    var map_table = initTable[Key, Value]()
    for k, v in node.fields:
      map_table[to_key(k)] = parse_json_internal(v)
    result = new_map_value(map_table)
  of json.JArray:
    var arr: seq[Value] = @[]
    for elem in node.elems:
      arr.add(parse_json_internal(elem))
    result = new_array_value(arr)

proc to_json*(val: Value): string =
  case val.kind:
  of VkNil:
    return "null"
  of VkBool:
    return $val.to_bool
  of VkInt:
    return $val.to_int
  of VkFloat:
    return $val.to_float
  of VkString:
    return json.escapeJson(val.str)
  of VkArray:
    var items: seq[string] = @[]
    for item in array_data(val):
      items.add(to_json(item))
    return "[" & items.join(",") & "]"
  of VkMap:
    var items: seq[string] = @[]
    let r = val.ref
    for k, v in r.map:
      # Convert Key to symbol string
      let key_val = cast[Value](k)  # Key is a packed symbol value
      let key_str = if key_val.kind == VkSymbol:
        key_val.str
      else:
        "unknown_key"
      items.add("\"" & json.escapeJson(key_str) & "\":" & to_json(v))
    return "{" & items.join(",") & "}"
  else:
    return "null"

proc new_map_from_pairs(pairs: seq[(string, string)]): Value =
  var table = initTable[Key, Value]()
  for (k, v) in pairs:
    table[k.to_key()] = v.to_value()
  result = new_map_value(table)

proc parse_form_body(body: string): Value =
  var pairs: seq[(string, string)] = @[]
  for key, val in decodeData(body):
    pairs.add((key, val))
  if pairs.len == 0:
    return NIL
  new_map_from_pairs(pairs)

proc parse_body_params(body: string, content_type: string): Value =
  let trimmed = body.strip()
  if trimmed.len == 0:
    return NIL
  let normalized = content_type.toLowerAscii()
  if normalized.contains("application/json"):
    try:
      return parse_json(trimmed)
    except CatchableError:
      return NIL
  let is_form = normalized.contains("application/x-www-form-urlencoded") or
                (normalized.len == 0 and trimmed.contains("="))
  if is_form:
    return parse_form_body(trimmed)
  return NIL

proc server_request_get_prop(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool, prop: Key): Value =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "ServerRequest method requires self")
  let self_val = get_positional_arg(args, 0, has_keyword_args)
  if self_val.kind != VkInstance:
    raise new_exception(types.Exception, "ServerRequest methods must be called on an instance")
  return instance_props(self_val).getOrDefault(prop, NIL)

proc server_request_path(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  server_request_get_prop(vm, args, arg_count, has_keyword_args, "path".to_key())

proc server_request_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  server_request_get_prop(vm, args, arg_count, has_keyword_args, "method".to_key())

proc server_request_url(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  server_request_get_prop(vm, args, arg_count, has_keyword_args, "url".to_key())

proc server_request_params(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  server_request_get_prop(vm, args, arg_count, has_keyword_args, "params".to_key())

proc server_request_headers(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  server_request_get_prop(vm, args, arg_count, has_keyword_args, "headers".to_key())

proc server_request_body(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  server_request_get_prop(vm, args, arg_count, has_keyword_args, "body".to_key())

proc server_request_body_params(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  server_request_get_prop(vm, args, arg_count, has_keyword_args, "body_params".to_key())

proc http_get*(url: string, headers: Table[string, string] = initTable[string, string]()): string =
  var client = newHttpClient()
  for k, v in headers:
    client.headers[k] = v
  result = client.getContent(url)
  client.close()

proc http_get_json*(url: string, headers: Table[string, string] = initTable[string, string]()): Value =
  let content = http_get(url, headers)
  return parse_json(content)

proc http_post*(url: string, body: string = "", headers: Table[string, string] = initTable[string, string]()): string =
  var client = newHttpClient()
  for k, v in headers:
    client.headers[k] = v
  result = client.postContent(url, body)
  client.close()

proc http_post_json*(url: string, body: Value, headers: Table[string, string] = initTable[string, string]()): Value =
  var hdrs = headers
  hdrs["Content-Type"] = "application/json"
  let json_body = to_json(body)
  let content = http_post(url, json_body, hdrs)
  return parse_json(content)

proc http_put*(url: string, body: string = "", headers: Table[string, string] = initTable[string, string]()): string =
  var client = newHttpClient()
  for k, v in headers:
    client.headers[k] = v
  result = client.request(url, HttpPut, body).body
  client.close()

proc http_delete*(url: string, headers: Table[string, string] = initTable[string, string]()): string =
  var client = newHttpClient()
  for k, v in headers:
    client.headers[k] = v
  result = client.request(url, HttpDelete).body
  client.close()

# Helper function that uses Request class for consistency
proc vm_http_get_helper(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  # http_get(url, [headers]) -> Future[Response]
  if arg_count < 1:
    raise new_exception(types.Exception, "http_get requires at least a URL")

  let url = get_positional_arg(args, 0, has_keyword_args)
  var headers = if arg_count > 1: get_positional_arg(args, 1, has_keyword_args) else: NIL

  # Create Request
  var req_args = @[url, "GET".to_value()]
  if headers != NIL:
    req_args.add(headers)

  let request = call_native_fn(request_constructor, vm, req_args)

  # Send request
  return call_native_fn(request_send, vm, @[request])

proc vm_http_post_helper(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  # http_post(url, body, [headers]) -> Future[Response]
  if arg_count < 2:
    raise new_exception(types.Exception, "http_post requires URL and body")

  let url = get_positional_arg(args, 0, has_keyword_args)
  let body = get_positional_arg(args, 1, has_keyword_args)
  var headers = if arg_count > 2: get_positional_arg(args, 2, has_keyword_args) else: NIL

  # Create Request
  var req_args = @[url, "POST".to_value()]
  if headers != NIL:
    req_args.add(headers)
  else:
    let empty_map = new_map_value()
    map_data(empty_map) = Table[Key, Value]()
    req_args.add(empty_map)
  req_args.add(body)

  let request = call_native_fn(request_constructor, vm, req_args)

  # Send request
  return call_native_fn(request_send, vm, @[request])

# Native function wrappers for VM (backward compatibility)
proc vm_http_get(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if arg_count < 1:
      raise new_exception(types.Exception, "http_get requires at least 1 argument (url)")

    let url = get_positional_arg(args, 0, has_keyword_args).str
    var headers = initTable[string, string]()

    if arg_count > 1 and get_positional_arg(args, 1, has_keyword_args).kind == VkMap:
      let r = get_positional_arg(args, 1, has_keyword_args).ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    let content = http_get(url, headers)
    return new_str_value(content)

proc vm_http_get_json(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if arg_count < 1:
      raise new_exception(types.Exception, "http_get_json requires at least 1 argument (url)")

    let url = get_positional_arg(args, 0, has_keyword_args).str
    var headers = initTable[string, string]()

    if arg_count > 1 and get_positional_arg(args, 1, has_keyword_args).kind == VkMap:
      let r = get_positional_arg(args, 1, has_keyword_args).ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    return http_get_json(url, headers)

proc vm_http_post(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if arg_count < 1:
      raise new_exception(types.Exception, "http_post requires at least 1 argument (url)")

    let url = get_positional_arg(args, 0, has_keyword_args).str
    var body = ""
    var headers = initTable[string, string]()

    if arg_count > 1:
      let body_arg = get_positional_arg(args, 1, has_keyword_args)
      if body_arg.kind == VkString:
        body = body_arg.str
      elif body_arg.kind in {VkMap, VkArray}:
        body = to_json(body_arg)
        headers["Content-Type"] = "application/json"

    if arg_count > 2 and get_positional_arg(args, 2, has_keyword_args).kind == VkMap:
      let r = get_positional_arg(args, 2, has_keyword_args).ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    let content = http_post(url, body, headers)
    return new_str_value(content)

proc vm_http_post_json(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if arg_count < 2:
      raise new_exception(types.Exception, "http_post_json requires at least 2 arguments (url, body)")

    let url = get_positional_arg(args, 0, has_keyword_args).str
    let body = get_positional_arg(args, 1, has_keyword_args)
    var headers = initTable[string, string]()

    if arg_count > 2 and get_positional_arg(args, 2, has_keyword_args).kind == VkMap:
      let r = get_positional_arg(args, 2, has_keyword_args).ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    return http_post_json(url, body, headers)

proc vm_http_put(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if arg_count < 1:
      raise new_exception(types.Exception, "http_put requires at least 1 argument (url)")

    let url = get_positional_arg(args, 0, has_keyword_args).str
    var body = ""
    var headers = initTable[string, string]()

    if arg_count > 1 and get_positional_arg(args, 1, has_keyword_args).kind == VkString:
      body = get_positional_arg(args, 1, has_keyword_args).str

    if arg_count > 2 and get_positional_arg(args, 2, has_keyword_args).kind == VkMap:
      let r = get_positional_arg(args, 2, has_keyword_args).ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    let content = http_put(url, body, headers)
    return new_str_value(content)

proc vm_http_delete(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if arg_count < 1:
      raise new_exception(types.Exception, "http_delete requires at least 1 argument (url)")

    let url = get_positional_arg(args, 0, has_keyword_args).str
    var headers = initTable[string, string]()

    if arg_count > 1 and get_positional_arg(args, 1, has_keyword_args).kind == VkMap:
      let r = get_positional_arg(args, 1, has_keyword_args).ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    let content = http_delete(url, headers)
    return new_str_value(content)

proc vm_json_parse(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if arg_count < 1:
      raise new_exception(types.Exception, "json_parse requires 1 argument (json_string)")

    let json_arg = get_positional_arg(args, 0, has_keyword_args)
    if json_arg.kind != VkString:
      raise new_exception(types.Exception, "json_parse requires a string argument")

    return parse_json(json_arg.str)

proc vm_json_stringify(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if arg_count < 1:
      raise new_exception(types.Exception, "json_stringify requires 1 argument")

    let json_str = to_json(get_positional_arg(args, 0, has_keyword_args))
    return new_str_value(json_str)


proc init*(vm: ptr VirtualMachine): Namespace {.exportc, dynlib.} =
  result = new_namespace("http")
  
  # HTTP functions
  var fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_get
  result["get".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_get_json
  result["get_json".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_post
  result["post".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_post_json
  result["post_json".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_put
  result["put".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_delete
  result["delete".to_key()] = fn.to_ref_value()

  # JSON functions
  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_json_parse
  result["json_parse".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_json_stringify
  result["json_stringify".to_key()] = fn.to_ref_value()

# Request constructor implementation
proc request_constructor(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  # new Request(url, [method], [headers], [body])
  if arg_count < 1:
    raise new_exception(types.Exception, "Request requires at least a URL")

  let url = get_positional_arg(args, 0, has_keyword_args)
  if url.kind != VkString:
    raise new_exception(types.Exception, "URL must be a string")

  # Create Request instance
  let request_class = block:
    {.cast(gcsafe).}:
      request_class_global
  let instance = new_instance_value(request_class)

  # Set properties
  instance_props(instance)["url".to_key()] = url

  # Set method (default to GET)
  if arg_count > 1:
    instance_props(instance)["method".to_key()] = get_positional_arg(args, 1, has_keyword_args)
  else:
    instance_props(instance)["method".to_key()] = "GET".to_value()

  # Set headers (default to empty map)
  if arg_count > 2:
    instance_props(instance)["headers".to_key()] = get_positional_arg(args, 2, has_keyword_args)
  else:
    let empty_map = new_map_value()
    map_data(empty_map) = Table[Key, Value]()
    instance_props(instance)["headers".to_key()] = empty_map
  
  # Set body (default to nil)
  if arg_count > 3:
    instance_props(instance)["body".to_key()] = get_positional_arg(args, 3, has_keyword_args)
  else:
    instance_props(instance)["body".to_key()] = NIL
  
  return instance

# Request.send method - sends the request and returns a Future[Response]
proc request_send(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "Request.send requires self")

  let request_obj = get_positional_arg(args, 0, has_keyword_args)
  if request_obj.kind != VkInstance:
    raise new_exception(types.Exception, "send can only be called on a Request instance")
  
  # Get request properties
  let url = instance_props(request_obj)["url".to_key()]
  let http_method = instance_props(request_obj)["method".to_key()]
  let headers = instance_props(request_obj)["headers".to_key()]
  let body = instance_props(request_obj)["body".to_key()]
  
  # Create HTTP client
  let client = newHttpClient()
  defer: client.close()
  
  # Set headers
  if headers.kind == VkMap:
    for k, v in map_data(headers):
      if v.kind == VkString:
        client.headers[cast[Value](k).str] = v.str
  
  # Prepare body
  var bodyStr = ""
  if body.kind == VkString:
    bodyStr = body.str
  elif body.kind == VkMap:
    # Convert map to JSON
    var jsonObj = newJObject()
    for k, v in map_data(body):
      let key_str = cast[Value](k).str
      case v.kind:
      of VkString:
        jsonObj[key_str] = newJString(v.str)
      of VkInt:
        jsonObj[key_str] = newJInt(v.int64)
      of VkFloat:
        jsonObj[key_str] = newJFloat(v.float)
      of VkBool:
        jsonObj[key_str] = newJBool(v.bool)
      of VkNil:
        jsonObj[key_str] = newJNull()
      else:
        jsonObj[key_str] = newJString($v)
    bodyStr = $jsonObj
    client.headers["Content-Type"] = "application/json"
  
  # Send request based on method
  let methodStr = if http_method.kind == VkString: http_method.str.toUpperAscii() else: "GET"
  let response = case methodStr:
    of "GET":
      client.get(url.str)
    of "POST":
      client.post(url.str, body = bodyStr)
    of "PUT":
      client.request(url.str, httpMethod = HttpPut, body = bodyStr)
    of "DELETE":
      client.request(url.str, httpMethod = HttpDelete, body = bodyStr)
    of "PATCH":
      client.request(url.str, httpMethod = HttpPatch, body = bodyStr)
    of "HEAD":
      client.request(url.str, httpMethod = HttpHead)
    of "OPTIONS":
      client.request(url.str, httpMethod = HttpOptions)
    else:
      raise new_exception(types.Exception, "Unsupported HTTP method: " & methodStr)
  
  # Create Response instance
  let response_cls = block:
    {.cast(gcsafe).}:
      response_class_global
  let response_instance = new_instance_value(response_cls)
  instance_props(response_instance)["status".to_key()] = response.code.int.to_value()
  instance_props(response_instance)["body".to_key()] = response.body.to_value()
  
  # Convert headers to Gene map
  let headers_map = new_map_value()
  map_data(headers_map) = Table[Key, Value]()
  for k, v in response.headers.table:
    map_data(headers_map)[k.to_key()] = v[0].to_value()  # Take first value for multi-value headers
  instance_props(response_instance)["headers".to_key()] = headers_map
  
  # Create completed future with response
  let future = new_future_value()
  future.ref.future.complete(response_instance)
  return future

# Response constructor implementation
proc response_constructor(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  # new Response(status, body, [headers])
  if arg_count < 2:
    raise new_exception(types.Exception, "Response requires status and body")

  let status = get_positional_arg(args, 0, has_keyword_args)
  let body = get_positional_arg(args, 1, has_keyword_args)

  # Create Response instance
  let response_cls = block:
    {.cast(gcsafe).}:
      response_class_global
  let instance = new_instance_value(response_cls)

  # Set properties
  instance_props(instance)["status".to_key()] = status
  instance_props(instance)["body".to_key()] = body

  # Set headers (default to empty map)
  if arg_count > 2:
    instance_props(instance)["headers".to_key()] = get_positional_arg(args, 2, has_keyword_args)
  else:
    let empty_map = new_map_value()
    map_data(empty_map) = Table[Key, Value]()
    instance_props(instance)["headers".to_key()] = empty_map

  return instance

# Response.json method - parses body as JSON
proc response_json(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "Response.json requires self")

  let response_obj = get_positional_arg(args, 0, has_keyword_args)
  if response_obj.kind != VkInstance:
    raise new_exception(types.Exception, "json can only be called on a Response instance")

  let body = instance_props(response_obj)["body".to_key()]

  if body.kind != VkString:
    raise new_exception(types.Exception, "Response body must be a string to parse as JSON")

  # Parse JSON string into Gene map
  try:
    return parse_json(body.str)
  except JsonParsingError as e:
    raise new_exception(types.Exception, "Failed to parse JSON: " & e.msg)

proc init_http_classes*() =
  VmCreatedCallbacks.add proc() =
    # Ensure App is initialized
    if App == NIL or App.kind != VkApplication:
      return
    
    # Create Request class
    {.cast(gcsafe).}:
      request_class_global = new_class("Request")
      request_class_global.def_native_constructor(request_constructor)
      request_class_global.def_native_method("send", request_send)

    {.cast(gcsafe).}:
      server_request_class_global = new_class("ServerRequest")
      server_request_class_global.def_native_method("path", server_request_path)
      server_request_class_global.def_native_method("method", server_request_method)
      server_request_class_global.def_native_method("url", server_request_url)
      server_request_class_global.def_native_method("params", server_request_params)
      server_request_class_global.def_native_method("headers", server_request_headers)
      server_request_class_global.def_native_method("body", server_request_body)
      server_request_class_global.def_native_method("body_params", server_request_body_params)

    # Create Response class
    {.cast(gcsafe).}:
      response_class_global = new_class("Response")
      response_class_global.def_native_constructor(response_constructor)
      response_class_global.def_native_method("json", response_json)
    
    # Store classes in gene namespace
    let request_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      request_class_ref.class = request_class_global
    let server_request_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      server_request_class_ref.class = server_request_class_global
    let response_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      response_class_ref.class = response_class_global
    
    if App.app.gene_ns.kind == VkNamespace:
      App.app.gene_ns.ref.ns["Request".to_key()] = request_class_ref.to_ref_value()
      App.app.gene_ns.ref.ns["ServerRequest".to_key()] = server_request_class_ref.to_ref_value()
      App.app.gene_ns.ref.ns["Response".to_key()] = response_class_ref.to_ref_value()
    
    # Add helper functions to global namespace
    let get_fn = new_ref(VkNativeFn)
    get_fn.native_fn = vm_http_get_helper
    App.app.global_ns.ref.ns["http_get".to_key()] = get_fn.to_ref_value()

    let post_fn = new_ref(VkNativeFn)
    post_fn.native_fn = vm_http_post_helper
    App.app.global_ns.ref.ns["http_post".to_key()] = post_fn.to_ref_value()

    # Add server functions to global namespace
    let start_server_fn = new_ref(VkNativeFn)
    start_server_fn.native_fn = vm_start_server
    App.app.global_ns.ref.ns["start_server".to_key()] = start_server_fn.to_ref_value()

    let respond_fn = new_ref(VkNativeFn)
    respond_fn.native_fn = vm_respond
    App.app.global_ns.ref.ns["respond".to_key()] = respond_fn.to_ref_value()
    
    let redirect_fn = new_ref(VkNativeFn)
    redirect_fn.native_fn = vm_redirect
    App.app.global_ns.ref.ns["redirect".to_key()] = redirect_fn.to_ref_value()
  
  # Register HTTP poll handler with the scheduler (outside the VmCreatedCallback lambda)
  # This will be called by run_forever in the main scheduler loop
  register_scheduler_callback(process_pending_http_requests)

# Future-based handler execution system
import locks

type
  PendingHttpRequest = object
    request: Value              # The Gene request object
    nim_future: Future[Value]   # Nim future to complete with response
    processed: bool             # Whether handler has been executed

# Global storage for handler and VM reference
var gene_handler_global: Value = NIL
var gene_vm_global: ptr VirtualMachine = nil

# Pending HTTP requests awaiting handler execution
var pending_http_requests: seq[PendingHttpRequest]
var pending_lock: Lock
initLock(pending_lock)

# Process pending HTTP requests (called from VM's poll_event_loop via EventLoopCallbacks)
# This executes the Gene handler and completes the Nim future
proc process_pending_http_requests*(vm: ptr VirtualMachine) {.gcsafe.} =
  {.cast(gcsafe).}:
    if pending_http_requests.len == 0:
      return

    withLock(pending_lock):
      var i = 0
      while i < pending_http_requests.len:
        var req = addr pending_http_requests[i]
        if not req.processed:
          req.processed = true

          # Execute the handler
          var result: Value
          if gene_handler_global.kind != VkNil:
            try:
              result = execute_gene_function(vm, gene_handler_global, @[req.request])
            except CatchableError as e:
              # Create error response
              let error_response = block:
                let instance_class = (if server_response_class_global != nil: server_response_class_global else: new_class("ServerResponse"))
                let instance = new_instance_value(instance_class)
                instance_props(instance)["status".to_key()] = 500.to_value()
                instance_props(instance)["body".to_key()] = ("Internal Server Error: " & e.msg).to_value()
                instance_props(instance)["headers".to_key()] = new_map_value()
                instance
              result = error_response
          else:
            result = NIL
          
          # Complete the Nim future - this will wake up the async HTTP handler
          req.nim_future.complete(result)
          
          # Remove from pending list
          pending_http_requests.delete(i)
          continue
        
        i.inc()

# Execute a Gene function in VM context
proc execute_gene_function(vm: ptr VirtualMachine, fn: Value, args: seq[Value]): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    case fn.kind:
    of VkNativeFn:
      return call_native_fn(fn.ref.native_fn, vm, args)
    of VkFunction:
      # Execute Gene function using the VM's exec_function method
      let result = vm.exec_function(fn, args)
      return result
    of VkClass:
      # If it's a class, try to call its `call` method
      if fn.ref.class.methods.contains("call".to_key()):
        let call_method = fn.ref.class.methods["call".to_key()].callable
        return execute_gene_function(vm, call_method, args)
      else:
        return NIL
    of VkInstance:
      # If it's an instance, try to call its `call` method
      let inst_class = instance_class(fn)
      if inst_class.methods.contains("call".to_key()):
        let call_method = inst_class.methods["call".to_key()].callable
        # Use exec_method to properly set up the scope with self bound
        # fn is the instance, args are the additional arguments
        let result = vm.exec_method(call_method, fn, args)
        return result
      else:
        return NIL
    else:
      return NIL

# HTTP Server implementation
proc create_server_request(req: asynchttpserver.Request): Value =
  # Create ServerRequest instance
  let request_cls = block:
    {.cast(gcsafe).}:
      server_request_class_global
  let instance = new_instance_value(request_cls)
  
  # Set properties
  instance_props(instance)["method".to_key()] = ($req.reqMethod).to_value()
  instance_props(instance)["url".to_key()] = req.url.path.to_value()
  instance_props(instance)["path".to_key()] = req.url.path.to_value()
  
  # Parse query parameters
  let params_map = new_map_value()
  map_data(params_map) = Table[Key, Value]()
  if req.url.query != "":
    for key, val in decodeData(req.url.query):
      map_data(params_map)[key.to_key()] = val.to_value()
  instance_props(instance)["params".to_key()] = params_map
  
  # Convert headers to Gene map
  let headers_map = new_map_value()
  map_data(headers_map) = Table[Key, Value]()
  for k, v in req.headers.table:
    map_data(headers_map)[k.to_key()] = v[0].to_value()  # Take first value
  instance_props(instance)["headers".to_key()] = headers_map
  
  # Store body if present
  let body_content = req.body
  instance_props(instance)["body".to_key()] = body_content.to_value()
  
  var content_type = ""
  if req.headers.hasKey("Content-Type"):
    content_type = req.headers["Content-Type"]
  instance_props(instance)["body_params".to_key()] = parse_body_params(body_content, content_type)
  
  return instance

proc handle_request(req: asynchttpserver.Request) {.async, gcsafe.} =
  {.cast(gcsafe).}:
    # Convert async request to Gene request
    let gene_req = create_server_request(req)

    # Call the handler
    var response: Value = NIL

    # If we have a native handler, call it directly
    if server_handler != nil:
      try:
        response = server_handler(gene_req)
      except CatchableError as e:
        # Return 500 error on exception
        await req.respond(Http500, "Internal Server Error: " & e.msg)
        return
    # If we have a Gene function handler, add to pending requests
    elif gene_handler_global.kind != VkNil:
      # Create a Nim future to await the response
      let nim_future = newFuture[Value]("http_handler")
      
      # Add to pending requests list
      let pending_req = PendingHttpRequest(
        request: gene_req,
        nim_future: nim_future,
        processed: false
      )
      
      withLock(pending_lock):
        pending_http_requests.add(pending_req)
      
      # Await the Nim future (will be completed when process_pending_http_requests runs)
      try:
        response = await nim_future
      except CatchableError as e:
        await req.respond(Http500, "Internal Server Error: " & e.msg)
        return
    else:
      discard  # No handler configured
    
    # Handle the response
    if response == NIL:
      # No response, return 404
      await req.respond(Http404, "Not Found")
    elif response.kind == VkInstance:
      # Check if it's a ServerResponse
      let status_val = instance_props(response).getOrDefault("status".to_key(), 200.to_value())
      let body_val = instance_props(response).getOrDefault("body".to_key(), "".to_value())
      let headers_val = instance_props(response).getOrDefault("headers".to_key(), NIL)

      let status_code = if status_val.kind == VkInt:
        HttpCode(status_val.int64.int)
      else:
        Http200

      let body = if body_val.kind == VkString: body_val.str else: $body_val

      # Prepare headers
      var headers = newHttpHeaders()
      if headers_val.kind == VkMap:
        for k, v in map_data(headers_val):
          if v.kind == VkString:
            headers[cast[Value](k).str] = v.str

      await req.respond(status_code, body, headers)
    else:
      # Unknown response type
      await req.respond(Http500, "Invalid response type")

# Start HTTP server
proc vm_start_server(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 1:
    raise new_exception(types.Exception, "start_server requires at least a port")

  let port_val = get_positional_arg(args, 0, has_keyword_args)
  let handler = if arg_count > 1: get_positional_arg(args, 1, has_keyword_args) else: NIL
  
  let port = if port_val.kind == VkInt: port_val.int64.int else: 8080
  
  # Store the handler
  {.cast(gcsafe).}:
    # Store VM reference and handler globally for queue-based execution
    gene_vm_global = vm
    gene_handler_global = handler

    # Check handler type and set up appropriate handler
    case handler.kind:
    of VkNativeFn:
      # Native function - can be called directly
      let stored_vm = vm
      let stored_handler = handler

      server_handler = proc(req: Value): Value {.gcsafe.} =
        return call_native_fn(stored_handler.ref.native_fn, stored_vm, [req])
    of VkFunction, VkClass, VkInstance:
      # Gene function/class/instance - use queue system
      server_handler = nil  # Don't use native handler, will use queue
    of VkNil:
      # No handler
      server_handler = nil
    else:
      # Other handler types - use queue system
      server_handler = nil
  
  # Create and start server
  {.cast(gcsafe).}:
    http_server = newAsyncHttpServer()
    asyncCheck http_server.serve(Port(port), handle_request)
    # Give the event loop time to bind the server socket
    try:
      poll(100)  # Wait up to 100ms for server to bind
    except ValueError:
      discard

  echo "HTTP server started on port ", port
  return NIL

# Create a response
proc vm_respond(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 1:
    raise new_exception(types.Exception, "respond requires at least status or body")

  var status = 200
  var body = ""
  var headers = new_map_value()

  # Parse arguments
  if arg_count == 1:
    let arg = get_positional_arg(args, 0, has_keyword_args)
    if arg.kind == VkInt:
      # Just status code
      status = arg.int64.int
    elif arg.kind == VkString:
      # Just body (200 OK)
      body = arg.str
      status = 200
    else:
      body = $arg
  elif arg_count >= 2:
    # Status and body
    let status_arg = get_positional_arg(args, 0, has_keyword_args)
    if status_arg.kind == VkInt:
      status = status_arg.int64.int
    let body_arg = get_positional_arg(args, 1, has_keyword_args)
    if body_arg.kind == VkString:
      body = body_arg.str
    else:
      body = $body_arg

    # Optional headers
  if arg_count > 2:
    let headers_arg = get_positional_arg(args, 2, has_keyword_args)
    if headers_arg.kind == VkMap:
      headers = headers_arg
  
  # Create ServerResponse instance
  let instance_class = block:
    {.cast(gcsafe).}:
      (if server_response_class_global != nil: server_response_class_global else: new_class("ServerResponse"))
  let instance = new_instance_value(instance_class)
  
  instance_props(instance)["status".to_key()] = status.to_value()
  instance_props(instance)["body".to_key()] = body.to_value()
  instance_props(instance)["headers".to_key()] = headers
  
  return instance

proc vm_redirect(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "redirect requires a destination URL")

  let location_arg = get_positional_arg(args, 0, has_keyword_args)
  if location_arg.kind != VkString:
    raise new_exception(types.Exception, "redirect destination must be a string")

  var status = 302
  if get_positional_count(arg_count, has_keyword_args) > 1:
    let status_arg = get_positional_arg(args, 1, has_keyword_args)
    if status_arg.kind == VkInt:
      status = status_arg.int64.int
    else:
      raise new_exception(types.Exception, "redirect status must be an integer")

  let headers = new_map_value()
  map_data(headers)["Location".to_key()] = location_arg.str.to_value()

  let redirect_class = block:
    {.cast(gcsafe).}:
      (if server_response_class_global != nil: server_response_class_global else: new_class("ServerResponse"))
  let instance = new_instance_value(redirect_class)

  instance_props(instance)["status".to_key()] = status.to_value()
  instance_props(instance)["body".to_key()] = "".to_value()
  instance_props(instance)["headers".to_key()] = headers

  return instance

# Call init_http_classes to register the callback
init_http_classes()

{.pop.}
