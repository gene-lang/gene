import tables, strutils
import httpclient, uri
import std/json
import asynchttpserver, asyncdispatch
import asyncfutures  # Import asyncfutures explicitly
import nativesockets, net
import cgi

include ../gene/extension/boilerplate
import ../gene/compiler
import ../gene/vm
# Explicitly alias to use asyncfutures.Future in this module
type Future {.used.} = asyncfutures.Future

# Global variables to store classes
var request_class_global: Class
var response_class_global: Class
var server_request_class_global: Class
var server_response_class_global: Class

# Global HTTP server instance
var http_server: AsyncHttpServer
var server_handler: proc(req: Value): Value {.gcsafe.}
var stored_gene_handler: Value  # Store the Gene function/instance
var stored_vm: VirtualMachine   # Store VM reference for execution

# Forward declarations
proc request_constructor(self: VirtualMachine, args: Value): Value {.gcsafe.}
proc request_send(self: VirtualMachine, args: Value): Value {.gcsafe.}
proc response_constructor(self: VirtualMachine, args: Value): Value {.gcsafe.}
proc response_json(self: VirtualMachine, args: Value): Value {.gcsafe.}
proc vm_start_server(vm: VirtualMachine, args: Value): Value {.gcsafe.}
proc vm_respond(vm: VirtualMachine, args: Value): Value {.gcsafe.}
proc vm_run_forever(vm: VirtualMachine, args: Value): Value {.gcsafe.}
proc execute_gene_function(vm: VirtualMachine, fn: Value, args: seq[Value]): Value {.gcsafe.}

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
  of VkArray, VkVector:
    var items: seq[string] = @[]
    let r = val.ref
    for item in r.arr:
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
proc vm_http_get_helper(self: VirtualMachine, args: Value): Value {.gcsafe.} =
  # http_get(url, [headers]) -> Future[Response]
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "http_get requires at least a URL")
  
  let url = args.gene.children[0]
  var headers = if args.gene.children.len > 1: args.gene.children[1] else: NIL
  
  # Create Request
  let req_args = new_gene(NIL)
  req_args.children.add(url)
  req_args.children.add("GET".to_value())
  if headers != NIL:
    req_args.children.add(headers)
  
  let request = request_constructor(self, req_args.to_gene_value())
  
  # Send request
  let send_args = new_gene(NIL)
  send_args.children.add(request)
  return request_send(self, send_args.to_gene_value())

proc vm_http_post_helper(self: VirtualMachine, args: Value): Value {.gcsafe.} =
  # http_post(url, body, [headers]) -> Future[Response]
  if args.kind != VkGene or args.gene.children.len < 2:
    raise new_exception(types.Exception, "http_post requires URL and body")
  
  let url = args.gene.children[0]
  let body = args.gene.children[1]
  var headers = if args.gene.children.len > 2: args.gene.children[2] else: NIL
  
  # Create Request
  let req_args = new_gene(NIL)
  req_args.children.add(url)
  req_args.children.add("POST".to_value())
  if headers != NIL:
    req_args.children.add(headers)
  else:
    let empty_map = new_ref(VkMap)
    empty_map.map = Table[Key, Value]()
    req_args.children.add(empty_map.to_ref_value())
  req_args.children.add(body)
  
  let request = request_constructor(self, req_args.to_gene_value())
  
  # Send request
  let send_args = new_gene(NIL)
  send_args.children.add(request)
  return request_send(self, send_args.to_gene_value())

# Native function wrappers for VM (backward compatibility)
proc vm_http_get(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    # Args is a Gene with children as the arguments
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_get: args is not a Gene")
    
    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_get requires at least 1 argument (url)")
    
    let url = args.gene.children[0].str
    var headers = initTable[string, string]()
    
    if args.gene.children.len > 1 and args.gene.children[1].kind == VkMap:
      let r = args.gene.children[1].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    let content = http_get(url, headers)
    return new_str_value(content)

proc vm_http_get_json(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_get_json: args is not a Gene")
    
    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_get_json requires at least 1 argument (url)")
    
    let url = args.gene.children[0].str
    var headers = initTable[string, string]()
    
    if args.gene.children.len > 1 and args.gene.children[1].kind == VkMap:
      let r = args.gene.children[1].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    return http_get_json(url, headers)

proc vm_http_post(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_post: args is not a Gene")
    
    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_post requires at least 1 argument (url)")
    
    let url = args.gene.children[0].str
    var body = ""
    var headers = initTable[string, string]()
    
    if args.gene.children.len > 1:
      if args.gene.children[1].kind == VkString:
        body = args.gene.children[1].str
      elif args.gene.children[1].kind in {VkMap, VkVector, VkArray}:
        body = to_json(args.gene.children[1])
        headers["Content-Type"] = "application/json"
    
    if args.gene.children.len > 2 and args.gene.children[2].kind == VkMap:
      let r = args.gene.children[2].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    let content = http_post(url, body, headers)
    return new_str_value(content)

proc vm_http_post_json(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_post_json: args is not a Gene")
    
    if args.gene.children.len < 2:
      raise new_exception(types.Exception, "http_post_json requires at least 2 arguments (url, body)")
    
    let url = args.gene.children[0].str
    let body = args.gene.children[1]
    var headers = initTable[string, string]()
    
    if args.gene.children.len > 2 and args.gene.children[2].kind == VkMap:
      let r = args.gene.children[2].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    return http_post_json(url, body, headers)

proc vm_http_put(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_put: args is not a Gene")
    
    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_put requires at least 1 argument (url)")
    
    let url = args.gene.children[0].str
    var body = ""
    var headers = initTable[string, string]()
    
    if args.gene.children.len > 1 and args.gene.children[1].kind == VkString:
      body = args.gene.children[1].str
    
    if args.gene.children.len > 2 and args.gene.children[2].kind == VkMap:
      let r = args.gene.children[2].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    let content = http_put(url, body, headers)
    return new_str_value(content)

proc vm_http_delete(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_delete: args is not a Gene")
    
    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_delete requires at least 1 argument (url)")
    
    let url = args.gene.children[0].str
    var headers = initTable[string, string]()
    
    if args.gene.children.len > 1 and args.gene.children[1].kind == VkMap:
      let r = args.gene.children[1].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    let content = http_delete(url, headers)
    return new_str_value(content)

proc vm_json_parse(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "json_parse: args is not a Gene")
    
    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "json_parse requires 1 argument (json_string)")
    
    if args.gene.children[0].kind != VkString:
      raise new_exception(types.Exception, "json_parse requires a string argument")
    
    return parse_json(args.gene.children[0].str)

proc vm_json_stringify(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "json_stringify: args is not a Gene")
    
    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "json_stringify requires 1 argument")
    
    let json_str = to_json(args.gene.children[0])
    return new_str_value(json_str)

proc http_get_wrapper(vm: VirtualMachine, args: Value): Value {.gcsafe.} =
  # Wrapper that can be called directly
  vm_http_get(vm, args)

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
proc request_constructor(self: VirtualMachine, args: Value): Value =
  # new Request(url, [method], [headers], [body])
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "Request requires at least a URL")
  
  let url = args.gene.children[0]
  if url.kind != VkString:
    raise new_exception(types.Exception, "URL must be a string")
  
  # Create Request instance
  let instance = new_ref(VkInstance)
  {.cast(gcsafe).}:
    instance.instance_class = request_class_global
  
  # Set properties
  instance.instance_props["url".to_key()] = url
  
  # Set method (default to GET)
  if args.gene.children.len > 1:
    instance.instance_props["method".to_key()] = args.gene.children[1]
  else:
    instance.instance_props["method".to_key()] = "GET".to_value()
  
  # Set headers (default to empty map)
  if args.gene.children.len > 2:
    instance.instance_props["headers".to_key()] = args.gene.children[2]
  else:
    let empty_map = new_ref(VkMap)
    empty_map.map = Table[Key, Value]()
    instance.instance_props["headers".to_key()] = empty_map.to_ref_value()
  
  # Set body (default to nil)
  if args.gene.children.len > 3:
    instance.instance_props["body".to_key()] = args.gene.children[3]
  else:
    instance.instance_props["body".to_key()] = NIL
  
  return instance.to_ref_value()

# Request.send method - sends the request and returns a Future[Response]
proc request_send(self: VirtualMachine, args: Value): Value =
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "Request.send requires self")
  
  let request_obj = args.gene.children[0]
  if request_obj.kind != VkInstance:
    raise new_exception(types.Exception, "send can only be called on a Request instance")
  
  # Get request properties
  let url = request_obj.ref.instance_props["url".to_key()]
  let http_method = request_obj.ref.instance_props["method".to_key()]
  let headers = request_obj.ref.instance_props["headers".to_key()]
  let body = request_obj.ref.instance_props["body".to_key()]
  
  # Create HTTP client
  let client = newHttpClient()
  defer: client.close()
  
  # Set headers
  if headers.kind == VkMap:
    for k, v in headers.ref.map:
      if v.kind == VkString:
        client.headers[cast[Value](k).str] = v.str
  
  # Prepare body
  var bodyStr = ""
  if body.kind == VkString:
    bodyStr = body.str
  elif body.kind == VkMap:
    # Convert map to JSON
    var jsonObj = newJObject()
    for k, v in body.ref.map:
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
  let response_instance = new_ref(VkInstance)
  {.cast(gcsafe).}:
    response_instance.instance_class = response_class_global
  response_instance.instance_props["status".to_key()] = response.code.int.to_value()
  response_instance.instance_props["body".to_key()] = response.body.to_value()
  
  # Convert headers to Gene map
  let headers_map = new_ref(VkMap)
  headers_map.map = Table[Key, Value]()
  for k, v in response.headers.table:
    headers_map.map[k.to_key()] = v[0].to_value()  # Take first value for multi-value headers
  response_instance.instance_props["headers".to_key()] = headers_map.to_ref_value()
  
  # Create completed future with response
  let future = new_future_value()
  future.ref.future.complete(response_instance.to_ref_value())
  return future

# Response constructor implementation
proc response_constructor(self: VirtualMachine, args: Value): Value =
  # new Response(status, body, [headers])
  if args.kind != VkGene or args.gene.children.len < 2:
    raise new_exception(types.Exception, "Response requires status and body")
  
  let status = args.gene.children[0]
  let body = args.gene.children[1]
  
  # Create Response instance
  let instance = new_ref(VkInstance)
  {.cast(gcsafe).}:
    instance.instance_class = response_class_global
  
  # Set properties
  instance.instance_props["status".to_key()] = status
  instance.instance_props["body".to_key()] = body
  
  # Set headers (default to empty map)
  if args.gene.children.len > 2:
    instance.instance_props["headers".to_key()] = args.gene.children[2]
  else:
    let empty_map = new_ref(VkMap)
    empty_map.map = Table[Key, Value]()
    instance.instance_props["headers".to_key()] = empty_map.to_ref_value()
  
  return instance.to_ref_value()

# Response.json method - parses body as JSON
proc response_json(self: VirtualMachine, args: Value): Value =
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "Response.json requires self")
  
  let response_obj = args.gene.children[0]
  if response_obj.kind != VkInstance:
    raise new_exception(types.Exception, "json can only be called on a Response instance")
  
  let body = response_obj.ref.instance_props["body".to_key()]
  
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
    
    # Create Response class
    {.cast(gcsafe).}:
      response_class_global = new_class("Response")
      response_class_global.def_native_constructor(response_constructor)
      response_class_global.def_native_method("json", response_json)
    
    # Store classes in gene namespace
    let request_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      request_class_ref.class = request_class_global
    let response_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      response_class_ref.class = response_class_global
    
    if App.app.gene_ns.kind == VkNamespace:
      App.app.gene_ns.ref.ns["Request".to_key()] = request_class_ref.to_ref_value()
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
    
    # Add run_forever to gene namespace for gene/run_forever
    if App.app.gene_ns.kind == VkNamespace:
      let run_forever_fn = new_ref(VkNativeFn)
      run_forever_fn.native_fn = vm_run_forever
      App.app.gene_ns.ref.ns["run_forever".to_key()] = run_forever_fn.to_ref_value()

# Queue-based handler execution system
import locks, deques

type
  HandlerRequest = object
    request: Value
    response: ptr Channel[Value]
    completed: ptr bool

# Global storage for handler and VM reference
var gene_handler_global: Value = NIL
var gene_vm_global: VirtualMachine = nil

# Queue for pending handler requests
var handler_queue {.threadvar.}: Deque[HandlerRequest]
var queue_lock: Lock
initLock(queue_lock)

# Process pending handler requests (called from VM main loop)
proc process_handler_queue*(vm: VirtualMachine) {.exportc, dynlib.} =
  {.cast(gcsafe).}:
    withLock(queue_lock):
      while handler_queue.len > 0:
        let req = handler_queue.popFirst()
        
        # Execute the handler
        var result: Value
        if gene_handler_global.kind != VkNil:
          result = execute_gene_function(vm, gene_handler_global, @[req.request])
        else:
          result = ("404 Not Found").to_value()
        
        # Send response back
        req.response[].send(result)
        req.completed[] = true

# Execute a Gene function in VM context
proc execute_gene_function(vm: VirtualMachine, fn: Value, args: seq[Value]): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    case fn.kind:
    of VkNativeFn:
      let gene_args = new_gene(NIL)
      for arg in args:
        gene_args.children.add(arg)
      return fn.ref.native_fn(vm, gene_args.to_gene_value())
    of VkFunction:
      # Execute Gene function using the VM's exec_function method
      return vm.exec_function(fn, args)
    of VkClass:
      # If it's a class, try to call its `call` method
      if fn.ref.class.methods.contains("call".to_key()):
        let call_method = fn.ref.class.methods["call".to_key()].callable
        return execute_gene_function(vm, call_method, args)
      else:
        return NIL
    of VkInstance:
      # If it's an instance, try to call its `call` method
      let instance = fn.ref
      if instance.instance_class.methods.contains("call".to_key()):
        let call_method = instance.instance_class.methods["call".to_key()].callable
        # Prepend instance as first argument
        var new_args = @[fn]
        new_args.add(args)
        return execute_gene_function(vm, call_method, new_args)
      else:
        return NIL
    else:
      return NIL

# HTTP Server implementation
proc create_server_request(req: asynchttpserver.Request): Value =
  # Create ServerRequest instance
  let instance = new_ref(VkInstance)
  {.cast(gcsafe).}:
    if server_request_class_global != nil:
      instance.instance_class = server_request_class_global
    else:
      # Create a temporary class if not initialized
      instance.instance_class = new_class("ServerRequest")
  
  # Set properties
  instance.instance_props["method".to_key()] = ($req.reqMethod).to_value()
  instance.instance_props["url".to_key()] = req.url.path.to_value()
  instance.instance_props["path".to_key()] = req.url.path.to_value()
  
  # Parse query parameters
  let params_map = new_ref(VkMap)
  params_map.map = Table[Key, Value]()
  if req.url.query != "":
    for key, val in decodeData(req.url.query):
      params_map.map[key.to_key()] = val.to_value()
  instance.instance_props["params".to_key()] = params_map.to_ref_value()
  
  # Convert headers to Gene map
  let headers_map = new_ref(VkMap)
  headers_map.map = Table[Key, Value]()
  for k, v in req.headers.table:
    headers_map.map[k.to_key()] = v[0].to_value()  # Take first value
  instance.instance_props["headers".to_key()] = headers_map.to_ref_value()
  
  # Store body if present
  instance.instance_props["body".to_key()] = req.body.to_value()
  
  return instance.to_ref_value()

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
    # If we have a Gene function handler, use the queue system
    elif gene_handler_global.kind != VkNil:
      # Create response channel
      var response_channel: Channel[Value]
      response_channel.open()
      var completed = false
      
      # Queue the request
      let handler_req = HandlerRequest(
        request: gene_req,
        response: addr response_channel,
        completed: addr completed
      )
      
      withLock(queue_lock):
        handler_queue.addLast(handler_req)
      
      # Wait for response (with timeout)
      var timeout = 0
      while not completed and timeout < 1000:  # 10 second timeout
        await sleepAsync(10)
        timeout += 1
      
      if completed:
        response = response_channel.recv()
      else:
        response = ("504 Gateway Timeout").to_value()
      
      response_channel.close()
    
    # Handle the response
    if response == NIL:
      # No response, return 404
      await req.respond(Http404, "Not Found")
    elif response.kind == VkInstance:
      # Check if it's a ServerResponse
      let status_val = response.ref.instance_props.getOrDefault("status".to_key(), 200.to_value())
      let body_val = response.ref.instance_props.getOrDefault("body".to_key(), "".to_value())
      let headers_val = response.ref.instance_props.getOrDefault("headers".to_key(), NIL)
      
      let status_code = if status_val.kind == VkInt: 
        HttpCode(status_val.int64.int)
      else:
        Http200
      
      let body = if body_val.kind == VkString: body_val.str else: $body_val
      
      # Prepare headers
      var headers = newHttpHeaders()
      if headers_val.kind == VkMap:
        for k, v in headers_val.ref.map:
          if v.kind == VkString:
            headers[cast[Value](k).str] = v.str
      
      await req.respond(status_code, body, headers)
    else:
      # Unknown response type
      await req.respond(Http500, "Invalid response type")

# Start HTTP server
proc vm_start_server(vm: VirtualMachine, args: Value): Value {.gcsafe.} =
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "start_server requires at least a port")
  
  let port_val = args.gene.children[0]
  let handler = if args.gene.children.len > 1: args.gene.children[1] else: NIL
  
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
        let handler_args = new_gene(NIL)
        handler_args.children.add(req)
        return stored_handler.ref.native_fn(stored_vm, handler_args.to_gene_value())
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
  
  echo "HTTP server started on port ", port
  return NIL

# Create a response
proc vm_respond(vm: VirtualMachine, args: Value): Value {.gcsafe.} =
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "respond requires at least status or body")
  
  var status = 200
  var body = ""
  var headers = new_ref(VkMap)
  headers.map = Table[Key, Value]()
  
  # Parse arguments
  if args.gene.children.len == 1:
    let arg = args.gene.children[0]
    if arg.kind == VkInt:
      # Just status code
      status = arg.int64.int
    elif arg.kind == VkString:
      # Just body (200 OK)
      body = arg.str
      status = 200
    else:
      body = $arg
  elif args.gene.children.len >= 2:
    # Status and body
    if args.gene.children[0].kind == VkInt:
      status = args.gene.children[0].int64.int
    if args.gene.children[1].kind == VkString:
      body = args.gene.children[1].str
    else:
      body = $args.gene.children[1]
    
    # Optional headers
    if args.gene.children.len > 2 and args.gene.children[2].kind == VkMap:
      headers = args.gene.children[2].ref
  
  # Create ServerResponse instance
  let instance = new_ref(VkInstance)
  {.cast(gcsafe).}:
    if server_response_class_global != nil:
      instance.instance_class = server_response_class_global
    else:
      # Create temporary class
      instance.instance_class = new_class("ServerResponse")
  
  instance.instance_props["status".to_key()] = status.to_value()
  instance.instance_props["body".to_key()] = body.to_value()
  instance.instance_props["headers".to_key()] = headers.to_ref_value()
  
  return instance.to_ref_value()

# Run event loop forever
proc vm_run_forever(vm: VirtualMachine, args: Value): Value {.gcsafe.} =
  echo "Running event loop..."
  
  # Start a timer to periodically process the handler queue
  proc process_queue() {.async, gcsafe.} =
    while true:
      {.cast(gcsafe).}:
        # Process any pending handler requests
        if gene_vm_global != nil:
          process_handler_queue(gene_vm_global)
      await sleepAsync(10)  # Check every 10ms
  
  asyncCheck process_queue()
  runForever()
  return NIL

# Call init_http_classes to register the callback
init_http_classes()