## Gene VM bindings for OpenAI API
## Bridges the Nim OpenAI client to Gene's VM system

import tables, json
import ../../gene/types
import openai_client, streaming

# Helper to convert Gene Value to JsonNode
proc geneValueToJson*(value: Value): JsonNode =
  case value.kind
  of VkNil:
    result = newJNull()
  of VkBool:
    result = %*value.to_bool
  of VkInt:
    result = %*value.int
  of VkFloat:
    result = %*value.float
  of VkString:
    result = %*value.str
  of VkArray:
    var arr = newJArray()
    for item in value.ref.arr:
      arr.add(geneValueToJson(item))
    result = arr
  of VkMap:
    var obj = newJObject()
    for key, val in value.ref.map:
      obj[get_symbol(int(key))] = geneValueToJson(val)
    result = obj
  of VkGene:
    # Handle Gene expressions by evaluating them first
    # For now, convert to string
    result = %*($value)
  else:
    result = %*($value)

# Helper to convert JsonNode to Gene Value
proc jsonToGeneValue*(json: JsonNode): Value =
  case json.kind
  of JNull:
    result = NIL
  of JBool:
    result = json.getBool.to_value
  of JInt:
    result = json.getInt.to_value
  of JFloat:
    result = json.getFloat.to_value
  of JString:
    result = json.getStr.to_value
  of JArray:
    var arr = new_seq[Value]()
    for item in json:
      arr.add(jsonToGeneValue(item))
    result = new_array_value(arr)
  of JObject:
    var map = initTable[Key, Value]()
    for key, value in json:
      map[key.to_key()] = jsonToGeneValue(value)
    result = new_map_value(map)
  else:
    result = json.pretty.to_value

# Helper to create error objects
proc new_error*(message: string): Value =
  var error_obj = new_ref(VkInstance)
  error_obj.instance_props = initTable[Key, Value]()
  error_obj.instance_props["message".to_key()] = message.to_value
  error_obj.instance_props["type".to_key()] = "error".to_value
  result = error_obj.to_ref_value()

# OpenAI client class instance storage
var openai_clients: Table[int, OpenAIConfig] = initTable[int, OpenAIConfig]()
var next_client_id: int = 1

# Native function: Create new OpenAI client
proc vm_openai_new_client(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  var options: JsonNode = newJNull()

  if get_positional_count(arg_count, has_keyword_args) > 0:
    let options_val = get_positional_arg(args, 0, has_keyword_args)
    options = geneValueToJson(options_val)

  let config = buildOpenAIConfig(options)
  let client_id = next_client_id
  inc(next_client_id)

  openai_clients[client_id] = config

  # Return a Gene object representing the client
  var client_obj = new_ref(VkInstance)
  client_obj.instance_props = initTable[Key, Value]()
  client_obj.instance_props["client_id".to_key()] = client_id.to_value
  client_obj.instance_props["api_key".to_key()] = config.api_key.to_value
  client_obj.instance_props["base_url".to_key()] = config.base_url.to_value
  client_obj.instance_props["model".to_key()] = config.model.to_value

  result = client_obj.to_ref_value()

# Native function: Chat completion
proc vm_openai_chat(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if get_positional_count(arg_count, has_keyword_args) < 2:
    return new_error("OpenAI chat requires client and options arguments")

  let client_val = get_positional_arg(args, 0, has_keyword_args)
  let options_val = get_positional_arg(args, 1, has_keyword_args)

  if client_val.kind != VkInstance or not client_val.ref.instance_props.has_key("client_id".to_key()):
    return new_error("Invalid OpenAI client")

  let client_id = client_val.ref.instance_props["client_id".to_key()].int
  if not openai_clients.hasKey(client_id):
    return new_error("OpenAI client not found")

  let config = openai_clients[client_id]
  let options = geneValueToJson(options_val)

  try:
    let payload = buildChatPayload(config, options)
    let response = performRequest(config, "POST", "/chat/completions", payload)
    result = jsonToGeneValue(response)
  except OpenAIError as e:
    var error_obj = new_ref(VkInstance)
    error_obj.instance_props = initTable[Key, Value]()
    error_obj.instance_props["message".to_key()] = e.msg.to_value
    error_obj.instance_props["status".to_key()] = e.status.to_value
    if e.request_id != "":
      error_obj.instance_props["request_id".to_key()] = e.request_id.to_value
    result = error_obj.to_ref_value()
  except system.Exception as e:
    result = new_error("OpenAI chat failed: " & e.msg)

# Native function: Embeddings
proc vm_openai_embeddings(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if get_positional_count(arg_count, has_keyword_args) < 2:
    return new_error("OpenAI embeddings requires client and options arguments")

  let client_val = get_positional_arg(args, 0, has_keyword_args)
  let options_val = get_positional_arg(args, 1, has_keyword_args)

  if client_val.kind != VkInstance or not client_val.ref.instance_props.has_key("client_id".to_key()):
    return new_error("Invalid OpenAI client")

  let client_id = client_val.ref.instance_props["client_id".to_key()].int
  if not openai_clients.hasKey(client_id):
    return new_error("OpenAI client not found")

  let config = openai_clients[client_id]
  let options = geneValueToJson(options_val)

  try:
    let payload = buildEmbeddingsPayload(config, options)
    let response = performRequest(config, "POST", "/embeddings", payload)
    result = jsonToGeneValue(response)
  except OpenAIError as e:
    var error_obj = new_ref(VkInstance)
    error_obj.instance_props = initTable[Key, Value]()
    error_obj.instance_props["message".to_key()] = e.msg.to_value
    error_obj.instance_props["status".to_key()] = e.status.to_value
    result = error_obj.to_ref_value()
  except system.Exception as e:
    result = new_error("OpenAI embeddings failed: " & e.msg)

# Native function: Responses (for structured outputs)
proc vm_openai_respond(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if get_positional_count(arg_count, has_keyword_args) < 2:
    return new_error("OpenAI respond requires client and options arguments")

  let client_val = get_positional_arg(args, 0, has_keyword_args)
  let options_val = get_positional_arg(args, 1, has_keyword_args)

  if client_val.kind != VkInstance or not client_val.ref.instance_props.has_key("client_id".to_key()):
    return new_error("Invalid OpenAI client")

  let client_id = client_val.ref.instance_props["client_id".to_key()].int
  if not openai_clients.hasKey(client_id):
    return new_error("OpenAI client not found")

  let config = openai_clients[client_id]
  let options = geneValueToJson(options_val)

  try:
    let payload = buildResponsesPayload(config, options)
    let response = performRequest(config, "POST", "/responses", payload)
    result = jsonToGeneValue(response)
  except OpenAIError as e:
    var error_obj = new_ref(VkInstance)
    error_obj.instance_props = initTable[Key, Value]()
    error_obj.instance_props["message".to_key()] = e.msg.to_value
    error_obj.instance_props["status".to_key()] = e.status.to_value
    result = error_obj.to_ref_value()
  except system.Exception as e:
    result = new_error("OpenAI respond failed: " & e.msg)

# Instance methods for OpenAIClient class
proc vm_openai_client_chat(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    return new_error("OpenAI client chat requires self argument")

  let self_val = get_positional_arg(args, 0, has_keyword_args)
  if self_val.kind != VkInstance or not self_val.ref.instance_props.has_key("client_id".to_key()):
    return new_error("Invalid OpenAI client")

  let client_id = self_val.ref.instance_props["client_id".to_key()].int
  if not openai_clients.hasKey(client_id):
    return new_error("OpenAI client not found")

  let config = openai_clients[client_id]
  let options = if get_positional_count(arg_count, has_keyword_args) > 1:
    geneValueToJson(get_positional_arg(args, 1, has_keyword_args))
  else:
    %*{}

  try:
    let payload = buildChatPayload(config, options)
    let response = performRequest(config, "POST", "/chat/completions", payload)
    result = jsonToGeneValue(response)
  except OpenAIError as e:
    var error_obj = new_ref(VkInstance)
    error_obj.instance_props = initTable[Key, Value]()
    error_obj.instance_props["message".to_key()] = e.msg.to_value
    error_obj.instance_props["status".to_key()] = e.status.to_value
    if e.request_id != "":
      error_obj.instance_props["request_id".to_key()] = e.request_id.to_value
    result = error_obj.to_ref_value()
  except system.Exception as e:
    result = new_error("OpenAI client chat failed: " & e.msg)

proc vm_openai_client_embeddings(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    return new_error("OpenAI client embeddings requires self argument")

  let self_val = get_positional_arg(args, 0, has_keyword_args)
  if self_val.kind != VkInstance or not self_val.ref.instance_props.has_key("client_id".to_key()):
    return new_error("Invalid OpenAI client")

  let client_id = self_val.ref.instance_props["client_id".to_key()].int
  if not openai_clients.hasKey(client_id):
    return new_error("OpenAI client not found")

  let config = openai_clients[client_id]
  let options = if get_positional_count(arg_count, has_keyword_args) > 1:
    geneValueToJson(get_positional_arg(args, 1, has_keyword_args))
  else:
    %*{}

  try:
    let payload = buildEmbeddingsPayload(config, options)
    let response = performRequest(config, "POST", "/embeddings", payload)
    result = jsonToGeneValue(response)
  except OpenAIError as e:
    var error_obj = new_ref(VkInstance)
    error_obj.instance_props = initTable[Key, Value]()
    error_obj.instance_props["message".to_key()] = e.msg.to_value
    error_obj.instance_props["status".to_key()] = e.status.to_value
    result = error_obj.to_ref_value()
  except system.Exception as e:
    result = new_error("OpenAI client embeddings failed: " & e.msg)

proc vm_openai_client_respond(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    return new_error("OpenAI client respond requires self argument")

  let self_val = get_positional_arg(args, 0, has_keyword_args)
  if self_val.kind != VkInstance or not self_val.ref.instance_props.has_key("client_id".to_key()):
    return new_error("Invalid OpenAI client")

  let client_id = self_val.ref.instance_props["client_id".to_key()].int
  if not openai_clients.hasKey(client_id):
    return new_error("OpenAI client not found")

  let config = openai_clients[client_id]
  let options = if get_positional_count(arg_count, has_keyword_args) > 1:
    geneValueToJson(get_positional_arg(args, 1, has_keyword_args))
  else:
    %*{}

  try:
    let payload = buildResponsesPayload(config, options)
    let response = performRequest(config, "POST", "/responses", payload)
    result = jsonToGeneValue(response)
  except OpenAIError as e:
    var error_obj = new_ref(VkInstance)
    error_obj.instance_props = initTable[Key, Value]()
    error_obj.instance_props["message".to_key()] = e.msg.to_value
    error_obj.instance_props["status".to_key()] = e.status.to_value
    result = error_obj.to_ref_value()
  except system.Exception as e:
    result = new_error("OpenAI client respond failed: " & e.msg)

proc vm_openai_client_stream(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if get_positional_count(arg_count, has_keyword_args) < 2:
    return new_error("OpenAI client stream requires self and callback arguments")

  let self_val = get_positional_arg(args, 0, has_keyword_args)
  let callback_val = get_positional_arg(args, 1, has_keyword_args)

  if self_val.kind != VkInstance or not self_val.ref.instance_props.has_key("client_id".to_key()):
    return new_error("Invalid OpenAI client")

  if callback_val.kind != VkNativeFn and callback_val.kind != VkFunction:
    return new_error("Callback must be a function")

  let client_id = self_val.ref.instance_props["client_id".to_key()].int
  if not openai_clients.hasKey(client_id):
    return new_error("OpenAI client not found")

  let config = openai_clients[client_id]

  # Get optional options parameter
  var options = %*{}
  if get_positional_count(arg_count, has_keyword_args) > 2:
    let options_val = get_positional_arg(args, 2, has_keyword_args)
    options = geneValueToJson(options_val)

  # Add stream option
  options["stream"] = %*true
  let payload = buildChatPayload(config, options)

  try:
    # Create stream handler from Gene callback
    let handler = createGeneStreamHandler(vm, callback_val)

    # Perform streaming request synchronously
    performStreamingRequest(config, "/chat/completions", payload, handler)

    # Return success
    result = new_str_value("streaming completed")

  except OpenAIError as e:
    var error_obj = new_ref(VkInstance)
    error_obj.instance_props = initTable[Key, Value]()
    error_obj.instance_props["message".to_key()] = e.msg.to_value
    error_obj.instance_props["status".to_key()] = e.status.to_value
    if e.request_id != "":
      error_obj.instance_props["request_id".to_key()] = e.request_id.to_value
    result = error_obj.to_ref_value()
  except system.Exception as e:
    result = new_error("OpenAI client stream failed: " & e.msg)

# Native function: Stream chat completion
proc vm_openai_stream(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if get_positional_count(arg_count, has_keyword_args) < 3:
    return new_error("OpenAI stream requires client, options, and handler arguments")

  let client_val = get_positional_arg(args, 0, has_keyword_args)
  let options_val = get_positional_arg(args, 1, has_keyword_args)
  let handler_val = get_positional_arg(args, 2, has_keyword_args)

  if client_val.kind != VkInstance or not client_val.ref.instance_props.has_key("client_id".to_key()):
    return new_error("Invalid OpenAI client")

  if handler_val.kind != VkNativeFn and handler_val.kind != VkFunction:
    return new_error("Handler must be a function")

  let client_id = client_val.ref.instance_props["client_id".to_key()].int
  if not openai_clients.hasKey(client_id):
    return new_error("OpenAI client not found")

  let config = openai_clients[client_id]
  let options = geneValueToJson(options_val)

  try:
    var stream_options = options
    stream_options["stream"] = %*true
    let payload = buildChatPayload(config, stream_options)

    # Create stream handler from Gene callback
    let handler = createGeneStreamHandler(vm, handler_val)

    # Perform streaming request synchronously
    performStreamingRequest(config, "/chat/completions", payload, handler)

    # Return success
    result = new_str_value("streaming completed")

  except OpenAIError as e:
    var error_obj = new_ref(VkInstance)
    error_obj.instance_props = initTable[Key, Value]()
    error_obj.instance_props["message".to_key()] = e.msg.to_value
    error_obj.instance_props["status".to_key()] = e.status.to_value
    if e.request_id != "":
      error_obj.instance_props["request_id".to_key()] = e.request_id.to_value
    result = error_obj.to_ref_value()
  except system.Exception as e:
    result = new_error("OpenAI stream failed: " & e.msg)