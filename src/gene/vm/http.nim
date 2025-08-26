import std/[httpclient, uri, tables, strutils, json]

import ../types

# HTTP module for Gene
# Provides Request and Response classes for HTTP operations

# Global variables to store classes
var request_class_global: Class
var response_class_global: Class

# Request constructor
proc request_constructor(self: VirtualMachine, args: Value): Value {.gcsafe.} =
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
proc request_send(self: VirtualMachine, args: Value): Value {.gcsafe.} =
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
        jsonObj[key_str] = newJInt(v.int)
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

# Response constructor
proc response_constructor(self: VirtualMachine, args: Value): Value {.gcsafe.} =
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
proc response_json(self: VirtualMachine, args: Value): Value {.gcsafe.} =
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
    let jsonNode = parseJson(body.str)
    
    proc jsonToValue(node: JsonNode): Value =
      case node.kind:
      of JString:
        return node.str.to_value()
      of JInt:
        return node.num.to_value()
      of JFloat:
        return node.fnum.to_value()
      of JBool:
        return node.bval.to_value()
      of JNull:
        return NIL
      of JObject:
        let map = new_ref(VkMap)
        map.map = Table[Key, Value]()
        for k, v in node.fields:
          map.map[k.to_key()] = jsonToValue(v)
        return map.to_ref_value()
      of JArray:
        let arr = new_ref(VkArray)
        arr.arr = @[]
        for item in node.elems:
          arr.arr.add(jsonToValue(item))
        return arr.to_ref_value()
    
    return jsonToValue(jsonNode)
  except JsonParsingError as e:
    raise new_exception(types.Exception, "Failed to parse JSON: " & e.msg)
    
# Helper functions for quick HTTP requests
proc http_get(self: VirtualMachine, args: Value): Value {.gcsafe.} =
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

proc http_post(self: VirtualMachine, args: Value): Value {.gcsafe.} =
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

proc init_http*() =
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
    get_fn.native_fn = http_get
    App.app.global_ns.ref.ns["http_get".to_key()] = get_fn.to_ref_value()
    
    let post_fn = new_ref(VkNativeFn)
    post_fn.native_fn = http_post
    App.app.global_ns.ref.ns["http_post".to_key()] = post_fn.to_ref_value()

# Call init_http to register the callback
init_http()