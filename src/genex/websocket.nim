## WebSocket protocol implementation (RFC 6455)
## Pure Nim over asyncnet.AsyncSocket — no external dependencies.

import asyncnet, asyncdispatch
import checksums/sha1
import std/[base64, random, strutils, uri, net, httpcore]

const
  WS_MAGIC* = "258EAFA5-E914-47DA-95CA-5AB5DC76B97E"

  WsOpText*: uint8 = 0x1
  WsOpBinary*: uint8 = 0x2
  WsOpClose*: uint8 = 0x8
  WsOpPing*: uint8 = 0x9
  WsOpPong*: uint8 = 0xA

type
  WsFrame* = object
    fin*: bool
    opcode*: uint8
    payload*: string

  WebSocket* = ref object
    socket*: AsyncSocket
    is_client*: bool  # Client frames must be masked per RFC 6455
    closed*: bool
    recv_buffer: string

randomize()

# ---------------------------------------------------------------------------
# Sec-WebSocket-Accept key computation
# ---------------------------------------------------------------------------

proc compute_accept_key*(client_key: string): string =
  ## Compute Sec-WebSocket-Accept from Sec-WebSocket-Key (RFC 6455 §4.2.2)
  let hex = $secureHash(client_key & WS_MAGIC)
  var raw = newString(20)
  for i in 0..19:
    raw[i] = char(parseHexInt(hex[i*2 .. i*2+1]))
  base64.encode(raw)

proc generate_ws_key*(): string =
  ## Generate a random 16-byte Sec-WebSocket-Key (base64-encoded)
  var bytes: array[16, byte]
  for i in 0..15:
    bytes[i] = byte(rand(255))
  base64.encode(bytes)

# ---------------------------------------------------------------------------
# Frame encode / decode
# ---------------------------------------------------------------------------

proc encode_frame*(ws: WebSocket, opcode: uint8, payload: string): string =
  ## Encode a WebSocket frame. Client frames are masked per spec.
  var frame = newStringOfCap(2 + 8 + 4 + payload.len)

  # Byte 0: FIN + opcode
  frame.add(char(0x80'u8 or opcode))

  # Byte 1: MASK bit + payload length
  let mask_bit: uint8 = if ws.is_client: 0x80 else: 0
  if payload.len < 126:
    frame.add(char(mask_bit or uint8(payload.len)))
  elif payload.len < 65536:
    frame.add(char(mask_bit or 126'u8))
    frame.add(char(uint8((payload.len shr 8) and 0xFF)))
    frame.add(char(uint8(payload.len and 0xFF)))
  else:
    frame.add(char(mask_bit or 127'u8))
    for i in countdown(7, 0):
      frame.add(char(uint8((payload.len shr (i * 8)) and 0xFF)))

  # Client masking
  if ws.is_client:
    var mask_key: array[4, byte]
    for i in 0..3:
      mask_key[i] = byte(rand(255))
    for b in mask_key:
      frame.add(char(b))
    for i in 0..<payload.len:
      frame.add(char(byte(payload[i]) xor mask_key[i mod 4]))
  else:
    frame.add(payload)

  frame

proc encode_frame_raw*(opcode: uint8, payload: string, mask: bool): string =
  ## Encode a frame with explicit mask control (for testing).
  var frame = newStringOfCap(2 + 8 + 4 + payload.len)
  frame.add(char(0x80'u8 or opcode))
  let mask_bit: uint8 = if mask: 0x80 else: 0
  if payload.len < 126:
    frame.add(char(mask_bit or uint8(payload.len)))
  elif payload.len < 65536:
    frame.add(char(mask_bit or 126'u8))
    frame.add(char(uint8((payload.len shr 8) and 0xFF)))
    frame.add(char(uint8(payload.len and 0xFF)))
  else:
    frame.add(char(mask_bit or 127'u8))
    for i in countdown(7, 0):
      frame.add(char(uint8((payload.len shr (i * 8)) and 0xFF)))
  if mask:
    var mask_key: array[4, byte]
    for i in 0..3:
      mask_key[i] = byte(rand(255))
    for b in mask_key:
      frame.add(char(b))
    for i in 0..<payload.len:
      frame.add(char(byte(payload[i]) xor mask_key[i mod 4]))
  else:
    frame.add(payload)
  frame

proc decode_frame*(data: string): (WsFrame, int) =
  ## Decode one WebSocket frame from raw bytes.
  ## Returns (frame, bytes_consumed).  If data is incomplete, bytes_consumed = 0.
  if data.len < 2:
    return (WsFrame(), 0)

  let b0 = uint8(data[0])
  let b1 = uint8(data[1])

  let fin = (b0 and 0x80) != 0
  let opcode = b0 and 0x0F
  let masked = (b1 and 0x80) != 0
  var payload_len = int(b1 and 0x7F)
  var offset = 2

  if payload_len == 126:
    if data.len < 4: return (WsFrame(), 0)
    payload_len = (int(uint8(data[2])) shl 8) or int(uint8(data[3]))
    offset = 4
  elif payload_len == 127:
    if data.len < 10: return (WsFrame(), 0)
    payload_len = 0
    for i in 0..7:
      payload_len = (payload_len shl 8) or int(uint8(data[2 + i]))
    offset = 10

  var mask_key: array[4, byte]
  if masked:
    if data.len < offset + 4: return (WsFrame(), 0)
    for i in 0..3:
      mask_key[i] = uint8(data[offset + i])
    offset += 4

  if data.len < offset + payload_len:
    return (WsFrame(), 0)

  var payload = data[offset ..< offset + payload_len]
  if masked:
    for i in 0..<payload.len:
      payload[i] = char(byte(payload[i]) xor mask_key[i mod 4])

  (WsFrame(fin: fin, opcode: opcode, payload: payload), offset + payload_len)

# ---------------------------------------------------------------------------
# Async send helpers
# ---------------------------------------------------------------------------

proc ws_send*(ws: WebSocket, text: string) {.async.} =
  ## Send a text frame.
  if ws.closed:
    raise newException(IOError, "WebSocket is closed")
  let frame = encode_frame(ws, WsOpText, text)
  await ws.socket.send(frame)

proc ws_send_binary*(ws: WebSocket, data: string) {.async.} =
  ## Send a binary frame.
  if ws.closed:
    raise newException(IOError, "WebSocket is closed")
  let frame = encode_frame(ws, WsOpBinary, data)
  await ws.socket.send(frame)

proc ws_send_ping*(ws: WebSocket, data: string = "") {.async.} =
  if ws.closed: return
  let frame = encode_frame(ws, WsOpPing, data)
  await ws.socket.send(frame)

proc ws_send_pong*(ws: WebSocket, data: string = "") {.async.} =
  if ws.closed: return
  let frame = encode_frame(ws, WsOpPong, data)
  await ws.socket.send(frame)

# ---------------------------------------------------------------------------
# Async recv — returns next data or control frame
# ---------------------------------------------------------------------------

proc ws_recv*(ws: WebSocket): Future[WsFrame] {.async.} =
  ## Receive the next WebSocket frame.
  ## Ping frames are answered automatically; pong frames are consumed silently.
  ## Returns a Close frame (opcode 0x8) on disconnect.
  if ws.closed:
    return WsFrame(fin: true, opcode: WsOpClose, payload: "")

  while true:
    # Try to decode a complete frame from the buffer
    let (frame, consumed) = decode_frame(ws.recv_buffer)
    if consumed > 0:
      ws.recv_buffer = ws.recv_buffer[consumed .. ^1]

      case frame.opcode
      of WsOpPing:
        # Auto-reply pong and keep reading
        await ws_send_pong(ws, frame.payload)
        continue
      of WsOpPong:
        # Consume silently
        continue
      of WsOpClose:
        ws.closed = true
        # Echo close frame back
        try:
          let close_frame = encode_frame(ws, WsOpClose, "")
          await ws.socket.send(close_frame)
        except CatchableError:
          discard
        return frame
      else:
        return frame

    # Need more data
    let chunk = await ws.socket.recv(4096)
    if chunk.len == 0:
      ws.closed = true
      return WsFrame(fin: true, opcode: WsOpClose, payload: "")
    ws.recv_buffer.add(chunk)

# ---------------------------------------------------------------------------
# Close
# ---------------------------------------------------------------------------

proc ws_close*(ws: WebSocket) {.async.} =
  ## Initiate a graceful close.
  if ws.closed: return
  ws.closed = true
  try:
    let frame = encode_frame(ws, WsOpClose, "")
    await ws.socket.send(frame)
  except CatchableError:
    discard
  try:
    ws.socket.close()
  except CatchableError:
    discard

# ---------------------------------------------------------------------------
# Client connect
# ---------------------------------------------------------------------------

proc ws_connect*(url: string): Future[WebSocket] {.async.} =
  ## Open a WebSocket client connection to ws:// or wss:// URL.
  let parsed = parseUri(url)
  let scheme = parsed.scheme.toLowerAscii()
  let is_ssl = scheme == "wss"
  let host = parsed.hostname
  let port = if parsed.port.len > 0: parseInt(parsed.port)
             elif is_ssl: 443
             else: 80
  let path = if parsed.path.len > 0: parsed.path else: "/"
  let full_path = if parsed.query.len > 0: path & "?" & parsed.query else: path

  let socket = newAsyncSocket()

  when defined(ssl):
    if is_ssl:
      let ctx = newContext(protSSLv23, verifyMode = CVerifyNone)
      wrapSocket(ctx, socket)

  await socket.connect(host, Port(port))

  let key = generate_ws_key()
  var request = "GET " & full_path & " HTTP/1.1\c\L"
  request.add("Host: " & host & "\c\L")
  request.add("Upgrade: websocket\c\L")
  request.add("Connection: Upgrade\c\L")
  request.add("Sec-WebSocket-Key: " & key & "\c\L")
  request.add("Sec-WebSocket-Version: 13\c\L")
  request.add("\c\L")

  await socket.send(request)

  # Read HTTP 101 response
  let response_line = await socket.recvLine()
  if not response_line.contains("101"):
    socket.close()
    raise newException(IOError, "WebSocket upgrade failed: " & response_line)

  # Read response headers
  let expected_accept = compute_accept_key(key)
  var got_accept = false
  while true:
    let line = await socket.recvLine()
    if line.len == 0 or line == "\c\L":
      break
    if line.toLowerAscii().startsWith("sec-websocket-accept:"):
      let accept_value = line.split(":")[1].strip()
      if accept_value == expected_accept:
        got_accept = true

  if not got_accept:
    socket.close()
    raise newException(IOError, "WebSocket handshake failed: invalid accept key")

  return WebSocket(socket: socket, is_client: true, closed: false, recv_buffer: "")

# ---------------------------------------------------------------------------
# Server-side accept (upgrade existing HTTP connection)
# ---------------------------------------------------------------------------

proc ws_accept*(client: AsyncSocket, headers: HttpHeaders): Future[WebSocket] {.async.} =
  ## Accept a WebSocket upgrade on a server-side HTTP connection.
  ## The caller must pass the raw client socket and parsed request headers.

  # Verify Upgrade header
  let upgrade_val = headers.getOrDefault("Upgrade")
  if upgrade_val.toLowerAscii() != "websocket":
    raise newException(IOError, "Not a WebSocket upgrade request")

  let key = headers.getOrDefault("Sec-WebSocket-Key")
  if key.len == 0:
    raise newException(IOError, "Missing Sec-WebSocket-Key header")

  let accept_key = compute_accept_key(key)

  var response = "HTTP/1.1 101 Switching Protocols\c\L"
  response.add("Upgrade: websocket\c\L")
  response.add("Connection: Upgrade\c\L")
  response.add("Sec-WebSocket-Accept: " & accept_key & "\c\L")
  response.add("\c\L")

  await client.send(response)

  return WebSocket(socket: client, is_client: false, closed: false, recv_buffer: "")
