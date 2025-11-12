## Streaming implementation for OpenAI API
## Handles SSE (Server-Sent Events) and chunked streaming

import json, strutils

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

# Async stream reader for HTTP responses (placeholder for future async implementation)
proc readAsyncStream*(socket: pointer, handler: StreamHandler) =
  # Placeholder for future async implementation
  discard

# Utility for creating stream handlers in Gene
proc createStreamHandler*(vm: pointer, callback: pointer): StreamHandler =
  proc handler(event: StreamEvent) {.gcsafe.} =
    # This will be called from the VM side
    # The actual implementation will bridge to Gene's VM
    discard

  return handler