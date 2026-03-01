import std/json
import std/tables
import std/strutils
import std/httpclient
import std/os

import wrappers/openssl

import ./utils


type
  SlackVerifyResult* = object
    ok*: bool
    reason*: string

  SlackReplayGuard* = ref object
    ttl_sec*: int64
    seen*: Table[string, int64]


proc bytes_to_hex(bytes: openArray[byte]): string =
  const hex_chars = "0123456789abcdef"
  result = newStringOfCap(bytes.len * 2)
  for b in bytes:
    result.add(hex_chars[(b shr 4) and 0x0F])
    result.add(hex_chars[b and 0x0F])

proc secure_eq(a: string; b: string): bool =
  if a.len != b.len:
    return false
  var diff = 0'u8
  for i in 0..<a.len:
    diff = diff or (cast[uint8](a[i]) xor cast[uint8](b[i]))
  diff == 0'u8

proc hmac_sha256_hex(key: string; message: string): string =
  var digest: array[EVP_MAX_MD_SIZE, byte]
  var digest_len: cuint = 0

  let key_ptr =
    if key.len == 0: nil
    else: cast[pointer](unsafeAddr key[0])
  let msg_ptr =
    if message.len == 0: nil
    else: message.cstring

  discard HMAC(
    EVP_sha256(),
    key_ptr,
    key.len.cint,
    msg_ptr,
    message.len.csize_t,
    cast[cstring](addr digest[0]),
    addr digest_len
  )

  bytes_to_hex(digest.toOpenArray(0, digest_len.int - 1))

proc compute_slack_signature*(signing_secret: string; timestamp_sec: string; raw_body: string): string =
  let base = "v0:" & timestamp_sec & ":" & raw_body
  "v0=" & hmac_sha256_hex(signing_secret, base)

proc parse_unix_sec(ts: string): int64 =
  try:
    parseInt(ts).int64
  except ValueError:
    -1

proc verify_slack_signature*(
  signing_secret: string;
  timestamp_sec: string;
  provided_signature: string;
  raw_body: string;
  now_ms = now_unix_ms();
  max_skew_sec = 300'i64
): SlackVerifyResult =
  if signing_secret.len == 0:
    return SlackVerifyResult(ok: false, reason: "missing signing secret")

  if provided_signature.len < 4 or not provided_signature.startsWith("v0="):
    return SlackVerifyResult(ok: false, reason: "invalid signature format")

  let ts = parse_unix_sec(timestamp_sec)
  if ts < 0:
    return SlackVerifyResult(ok: false, reason: "invalid timestamp")

  let now_sec = now_ms div 1000
  if abs(now_sec - ts) > max_skew_sec:
    return SlackVerifyResult(ok: false, reason: "stale timestamp")

  let expected = compute_slack_signature(signing_secret, timestamp_sec, raw_body)
  if not secure_eq(expected, provided_signature):
    return SlackVerifyResult(ok: false, reason: "signature mismatch")

  SlackVerifyResult(ok: true, reason: "")

proc is_slack_url_verification*(payload: JsonNode): bool =
  payload.kind == JObject and
    payload.hasKey("type") and
    payload["type"].kind == JString and
    payload["type"].getStr() == "url_verification"

proc slack_url_challenge*(payload: JsonNode): string =
  if payload.kind == JObject and payload.hasKey("challenge") and payload["challenge"].kind == JString:
    payload["challenge"].getStr()
  else:
    ""

proc slack_event_id*(payload: JsonNode): string =
  if payload.kind == JObject and payload.hasKey("event_id") and payload["event_id"].kind == JString:
    payload["event_id"].getStr()
  else:
    ""

proc json_get_str(obj: JsonNode; key: string): string =
  if obj.kind == JObject and obj.hasKey(key) and obj[key].kind == JString:
    obj[key].getStr()
  else:
    ""

proc slack_event_to_command*(payload: JsonNode; workspace_id = ""): CommandEnvelope =
  if payload.kind != JObject:
    raise newException(ValueError, "Slack payload must be an object")

  if is_slack_url_verification(payload):
    raise newException(ValueError, "url_verification payload does not carry a command")

  let payload_type = json_get_str(payload, "type")
  if payload_type != "event_callback":
    raise newException(ValueError, "Unsupported Slack payload type: " & payload_type)

  if not payload.hasKey("event") or payload["event"].kind != JObject:
    raise newException(ValueError, "Slack event_callback payload missing event object")

  let event = payload["event"]
  let event_type = json_get_str(event, "type")
  if event_type != "message":
    raise newException(ValueError, "Unsupported Slack event type: " & event_type)

  let subtype = json_get_str(event, "subtype")
  if subtype == "bot_message" or json_get_str(event, "bot_id").len > 0:
    raise newException(ValueError, "Bot messages are ignored")

  let event_id = slack_event_id(payload)
  let resolved_workspace =
    if workspace_id.len > 0: workspace_id
    else: json_get_str(payload, "team_id")

  let channel = json_get_str(event, "channel")
  let user = json_get_str(event, "user")
  let text = json_get_str(event, "text")
  let ts = json_get_str(event, "ts")
  let thread_ts = block:
    let v = json_get_str(event, "thread_ts")
    if v.len > 0: v
    else: ts

  if channel.len == 0 or user.len == 0 or text.len == 0:
    raise newException(ValueError, "Slack message missing required user/channel/text")

  let metadata = %*{
    "payload_type": payload_type,
    "event_type": event_type,
    "subtype": subtype,
    "team_id": json_get_str(payload, "team_id"),
    "event_time": if payload.hasKey("event_time"): payload["event_time"] else: newJInt(0),
    "slack_ts": ts
  }

  new_command_envelope(
    command_id = if event_id.len > 0: event_id else: "slack-" & $now_unix_ms(),
    source = CsSlack,
    workspace_id = resolved_workspace,
    user_id = user,
    channel_id = channel,
    thread_id = thread_ts,
    text = text,
    metadata = metadata
  )

proc new_slack_replay_guard*(ttl_sec = 3600'i64): SlackReplayGuard =
  SlackReplayGuard(ttl_sec: ttl_sec, seen: initTable[string, int64]())

proc cleanup_replay_guard*(guard: SlackReplayGuard; now_ms = now_unix_ms()) =
  if guard.isNil:
    return
  let cutoff = now_ms - (guard.ttl_sec * 1000)
  var to_remove: seq[string] = @[]
  for event_id, seen_at in guard.seen:
    if seen_at < cutoff:
      to_remove.add(event_id)
  for event_id in to_remove:
    guard.seen.del(event_id)

proc mark_or_is_duplicate*(guard: SlackReplayGuard; event_id: string; now_ms = now_unix_ms()): bool =
  if guard.isNil:
    return false
  if event_id.len == 0:
    return false

  guard.cleanup_replay_guard(now_ms)

  if guard.seen.hasKey(event_id):
    return true

  guard.seen[event_id] = now_ms
  false


# --- Slack reply adapter ---

type
  SlackReplyTarget* = object
    channel*: string
    thread_ts*: string

  SlackReplyResult* = object
    ok*: bool
    error*: string
    ts*: string

  SlackClient* = ref object
    bot_token*: string
    base_url*: string


proc new_slack_client*(bot_token = ""; base_url = "https://slack.com"): SlackClient =
  let token =
    if bot_token.len > 0: bot_token
    else: getEnv("SLACK_BOT_TOKEN")
  SlackClient(bot_token: token, base_url: base_url)

proc reply_target_from_envelope*(envelope: CommandEnvelope): SlackReplyTarget =
  SlackReplyTarget(
    channel: envelope.channel_id,
    thread_ts: envelope.thread_id
  )

proc slack_reply*(client: SlackClient; target: SlackReplyTarget; text: string): SlackReplyResult =
  if client.isNil or client.bot_token.len == 0:
    return SlackReplyResult(ok: false, error: "missing bot token")
  if target.channel.len == 0:
    return SlackReplyResult(ok: false, error: "missing channel")
  if text.len == 0:
    return SlackReplyResult(ok: false, error: "empty message")

  let payload = %*{
    "channel": target.channel,
    "text": text
  }
  if target.thread_ts.len > 0:
    payload["thread_ts"] = %target.thread_ts

  let url = client.base_url & "/api/chat.postMessage"
  var http = newHttpClient()
  try:
    http.headers = newHttpHeaders({
      "Content-Type": "application/json; charset=utf-8",
      "Authorization": "Bearer " & client.bot_token
    })
    let response = http.request(url, httpMethod = HttpPost, body = $payload)
    let body = parseJson(response.body)

    if body.kind == JObject and body.hasKey("ok") and body["ok"].kind == JBool and body["ok"].getBool():
      let ts =
        if body.hasKey("ts") and body["ts"].kind == JString: body["ts"].getStr()
        else: ""
      SlackReplyResult(ok: true, error: "", ts: ts)
    else:
      let err =
        if body.kind == JObject and body.hasKey("error") and body["error"].kind == JString:
          body["error"].getStr()
        else:
          "unknown Slack API error"
      SlackReplyResult(ok: false, error: err)
  except CatchableError as e:
    SlackReplyResult(ok: false, error: e.msg)
  finally:
    http.close()

proc slack_ack_json*(): JsonNode =
  ## Return the minimal 200 OK body Slack expects within 3 seconds.
  %*{"ok": true}
