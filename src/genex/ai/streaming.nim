## Streaming implementation for OpenAI API
## Handles SSE (Server-Sent Events) and chunked streaming

import json, strutils, httpclient, tables
import ../../gene/types
import openai_client

type
  StreamEvent* = ref object
    event*: string
    data*: JsonNode
    done*: bool

  StreamHandler* = proc(event: StreamEvent) {.gcsafe.}

# SSE parsing utilities
proc parseSSELine*(line: string): StreamEvent =
  if line.len == 0:
    return StreamEvent(event: "keepalive", done: false)

  if line.startsWith("event: "):
    return StreamEvent(event: line[7..line.len-1], done: false)

  if line.startsWith("data: "):
    let dataStr = line[6..line.len-1]
    if dataStr == "[DONE]":
      return StreamEvent(event: "done", done: true)

    try:
      let data = parseJson(dataStr)
      return StreamEvent(event: "data", data: data, done: false)
    except:
      return StreamEvent(event: "error", done: false)

  return StreamEvent(event: "unknown", done: false)

# Stream processing for both SSE and chunked responses
proc processStream*(body: string, handler: StreamHandler) =
  var buffer = ""
  var lines = body.splitLines()

  for line in lines:
    let line = line.strip()
    if line.len == 0:
      continue

    let event = parseSSELine(line)

    when defined(debug):
      echo "DEBUG: Stream event: ", event.event, " done: ", event.done

    if event.event in ["data", "done", "error"]:
      handler(event)

    if event.done:
      break

# HTTP streaming request processor
proc performStreamingRequest*(config: OpenAIConfig, endpoint: string,
                             payload: JsonNode, handler: StreamHandler) =
  var client = newHttpClient(timeout = config.timeout_ms)

  try:
    let url = config.base_url & endpoint
    let body = $payload

    var headers = newHttpHeaders()
    for key, value in config.headers:
      headers[key] = value

    when defined(debug):
      echo "DEBUG: OpenAI Streaming Request: POST ", url
      echo "DEBUG: Headers: ", headers
      echo "DEBUG: Body: ", body[0..min(body.len, 200)] & (if body.len > 200: "..." else: "")

    # Make streaming request
    let response = client.request(url, httpMethod = HttpPost,
                                 body = body, headers = headers)

    when defined(debug):
      echo "DEBUG: Streaming response status: ", response.status

    let statusCode = response.status.split()[0]
    if statusCode != "200":
      let errorBody = try: parseJson(response.body) except: %*{"message": response.body}
      var errorMsg = ""
      if errorBody.hasKey("error") and errorBody["error"].hasKey("message"):
        errorMsg = errorBody["error"]["message"].getStr()
      else:
        errorMsg = errorBody.getStr()

      raise OpenAIError(
        msg: "OpenAI Streaming Error: " & errorMsg,
        status: parseInt(statusCode),
        provider_error: "streaming_error"
      )

    # Process the streaming response
    processStream(response.body, handler)

  except OpenAIError:
    raise
  except system.Exception as e:
    raise OpenAIError(
      msg: "Streaming network error: " & e.msg,
      status: -1,
      provider_error: "network"
    )
  finally:
    client.close()

# Convert Gene callback to StreamHandler
proc createGeneStreamHandler*(vm: VirtualMachine, callback: Value): StreamHandler =
  proc handler(event: StreamEvent) {.gcsafe.} =
    try:
      # Convert StreamEvent to Gene Value
      var event_obj = new_ref(VkInstance)
      event_obj.instance_props = initTable[Key, Value]()
      event_obj.instance_props["event".to_key()] = event.event.to_value
      event_obj.instance_props["done".to_key()] = event.done.to_value

      if event.data != nil:
        # Convert JSON to Gene value
        var map = initTable[Key, Value]()
        for key, value in event.data:
          map[key.to_key()] = case value.kind
          of JNull: NIL
          of JBool: value.getBool.to_value
          of JInt: value.getInt.to_value
          of JFloat: value.getFloat.to_value
          of JString: value.getStr.to_value
          of JArray:
            var arr = new_seq[Value]()
            for item in value:
              arr.add(case item.kind
              of JNull: NIL
              of JBool: item.getBool.to_value
              of JInt: item.getInt.to_value
              of JFloat: item.getFloat.to_value
              of JString: item.getStr.to_value
              else: item.pretty.to_value)
            new_array_value(arr)
          of JObject:
            var obj_map = initTable[Key, Value]()
            for k, v in value:
              obj_map[k.to_key()] = case v.kind
              of JNull: NIL
              of JBool: v.getBool.to_value
              of JInt: v.getInt.to_value
              of JFloat: v.getFloat.to_value
              of JString: v.getStr.to_value
              else: v.pretty.to_value
            new_map_value(obj_map)
          else: value.pretty.to_value
        event_obj.instance_props["data".to_key()] = new_map_value(map)
      else:
        event_obj.instance_props["data".to_key()] = NIL

      # Call the Gene callback
      if callback.kind == VkNativeFn:
        let args = [event_obj.to_ref_value()]
        discard call_native_fn(callback.ref.native_fn, vm, args)
      elif callback.kind == VkFunction:
        # For Gene functions, we need to execute them through the VM
        # For now, skip Gene function execution in streaming callbacks
        discard

    except system.Exception as e:
      when defined(debug):
        echo "DEBUG: Stream handler error: ", e.msg

  return handler