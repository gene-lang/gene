## Slack HTTP ingress: receives Slack events, verifies, deduplicates,
## dispatches to agent runtime, and replies via Slack Web API.
##
## The `handle_slack_request` proc is framework-agnostic: give it raw
## headers + body and it returns a structured response you can serialize
## into any HTTP response.

import std/json

import ./utils
import ./control_slack
import ./agent_runtime
import ./conversation


type
  SlackIngressConfig* = object
    signing_secret*: string
    bot_token*: string
    max_skew_sec*: int64

  SlackIngressResponse* = object
    status_code*: int
    body*: JsonNode
    error*: string

  SlackIngress* = ref object
    config*: SlackIngressConfig
    replay_guard*: SlackReplayGuard
    runtime*: AgentRuntime
    conversation_store*: ConversationStore
    slack_client*: SlackClient
    provider*: AgentProvider


proc new_slack_ingress*(
  signing_secret: string;
  bot_token: string;
  runtime: AgentRuntime;
  provider: AgentProvider;
  conversation_store: ConversationStore = nil;
  max_skew_sec = 300'i64
): SlackIngress =
  SlackIngress(
    config: SlackIngressConfig(
      signing_secret: signing_secret,
      bot_token: bot_token,
      max_skew_sec: max_skew_sec
    ),
    replay_guard: new_slack_replay_guard(),
    runtime: runtime,
    conversation_store: if conversation_store.isNil: new_conversation_store() else: conversation_store,
    slack_client: new_slack_client(bot_token = bot_token),
    provider: provider
  )

proc make_response(status: int; body: JsonNode; error = ""): SlackIngressResponse =
  SlackIngressResponse(status_code: status, body: body, error: error)

proc handle_slack_request*(
  ingress: SlackIngress;
  raw_body: string;
  timestamp_header: string;
  signature_header: string;
  now_ms = now_unix_ms()
): SlackIngressResponse =
  ## Process a raw Slack HTTP request. Returns a response to send back.
  ## Call this from your HTTP handler with the raw body and relevant headers:
  ##   X-Slack-Request-Timestamp -> timestamp_header
  ##   X-Slack-Signature -> signature_header
  ## Pass now_ms for deterministic testing.

  if ingress.isNil:
    return make_response(500, %*{"error": "ingress not configured"}, "ingress is nil")

  # 1. Verify signature
  let verify = verify_slack_signature(
    signing_secret = ingress.config.signing_secret,
    timestamp_sec = timestamp_header,
    provided_signature = signature_header,
    raw_body = raw_body,
    now_ms = now_ms,
    max_skew_sec = ingress.config.max_skew_sec
  )
  if not verify.ok:
    return make_response(401, %*{"error": "signature verification failed", "reason": verify.reason}, verify.reason)

  # 2. Parse payload
  var payload: JsonNode
  try:
    payload = parseJson(raw_body)
  except CatchableError as e:
    return make_response(400, %*{"error": "invalid JSON", "reason": e.msg}, e.msg)

  # 3. Handle URL verification challenge
  if is_slack_url_verification(payload):
    let challenge = slack_url_challenge(payload)
    return make_response(200, %*{"challenge": challenge})

  # 4. Deduplicate by event_id
  let event_id = slack_event_id(payload)
  if event_id.len > 0 and ingress.replay_guard.mark_or_is_duplicate(event_id):
    return make_response(200, slack_ack_json())

  # 5. Convert to CommandEnvelope
  var envelope: CommandEnvelope
  try:
    envelope = slack_event_to_command(payload)
  except ValueError as e:
    # Bot messages and unsupported types return 200 to avoid Slack retries
    return make_response(200, slack_ack_json(), e.msg)

  # 6. Record in conversation store
  if not ingress.conversation_store.isNil:
    let session_key = envelope.workspace_id & ":" & envelope.channel_id
    ingress.conversation_store.append_message(session_key, "user", envelope.text,
      %*{"user_id": envelope.user_id, "command_id": envelope.command_id})

  # 7. Start agent run
  let run_id = ingress.runtime.start_run(envelope)
  let step_result = ingress.runtime.run_until_terminal(run_id, ingress.provider)

  # 8. Record agent reply in conversation store
  if not ingress.conversation_store.isNil and step_result.message.len > 0:
    let session_key = envelope.workspace_id & ":" & envelope.channel_id
    ingress.conversation_store.append_message(session_key, "assistant", step_result.message,
      %*{"run_id": run_id})

  # 9. Reply to Slack
  if step_result.state == ArsCompleted and step_result.message.len > 0:
    let target = reply_target_from_envelope(envelope)
    let reply_result = ingress.slack_client.slack_reply(target, step_result.message)
    if not reply_result.ok:
      return make_response(200, %*{
        "ok": true,
        "run_id": run_id,
        "state": $step_result.state,
        "message": step_result.message,
        "warning": "reply failed: " & reply_result.error
      })

  # 10. Return ack (Slack requires 200 within 3 seconds; for long runs
  # you'd want to ack immediately and process async, but this is the
  # synchronous path for v1)
  make_response(200, %*{
    "ok": true,
    "run_id": run_id,
    "state": $step_result.state,
    "message": step_result.message
  })
