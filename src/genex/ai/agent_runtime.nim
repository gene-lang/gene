import std/tables
import std/json
import std/strutils

import ./utils
import ./tools


type
  AgentProvider* = proc(run_id: string; envelope: CommandEnvelope; history: seq[JsonNode]): JsonNode {.gcsafe.}

  AgentRunConfig* = object
    max_steps*: int
    max_tool_calls*: int

  AgentRunRecord* = ref object
    run*: AgentRun
    envelope*: CommandEnvelope
    config*: AgentRunConfig
    history*: seq[JsonNode]
    step_count*: int
    tool_call_count*: int
    final_output*: string

  AgentStepResult* = object
    run_id*: string
    state*: AgentRunState
    message*: string
    provider_response*: JsonNode
    tool_result*: JsonNode

  AgentRuntime* = ref object
    runs*: Table[string, AgentRunRecord]
    tool_registry*: ToolRegistry


proc new_agent_runtime*(tool_registry: ToolRegistry = nil): AgentRuntime =
  AgentRuntime(
    runs: initTable[string, AgentRunRecord](),
    tool_registry: tool_registry
  )

proc default_config(): AgentRunConfig =
  AgentRunConfig(max_steps: 16, max_tool_calls: 8)

proc add_history(run_record: AgentRunRecord; node: JsonNode) =
  if run_record.isNil:
    return
  run_record.history.add(node)

proc ensure_config(config: AgentRunConfig): AgentRunConfig =
  result = config
  if result.max_steps <= 0:
    result.max_steps = default_config().max_steps
  if result.max_tool_calls <= 0:
    result.max_tool_calls = default_config().max_tool_calls

proc start_run*(runtime: AgentRuntime; envelope: CommandEnvelope; run_id = ""; config = default_config()): string =
  if runtime.isNil:
    raise newException(ValueError, "AgentRuntime is nil")

  let rid =
    if run_id.len > 0: run_id
    elif envelope.command_id.len > 0: "run-" & envelope.command_id
    else: "run-" & $now_unix_ms()

  let run_record = AgentRunRecord(
    run: new_agent_run(rid),
    envelope: envelope,
    config: ensure_config(config),
    history: @[],
    step_count: 0,
    tool_call_count: 0,
    final_output: ""
  )

  run_record.add_history(%*{
    "type": "command",
    "text": envelope.text,
    "workspace_id": envelope.workspace_id,
    "user_id": envelope.user_id,
    "channel_id": envelope.channel_id,
    "thread_id": envelope.thread_id
  })

  runtime.runs[rid] = run_record
  rid

proc get_run*(runtime: AgentRuntime; run_id: string): AgentRunRecord =
  if runtime.isNil or run_id.len == 0:
    return nil
  runtime.runs.getOrDefault(run_id, nil)

proc cancel_run*(runtime: AgentRuntime; run_id: string): bool =
  let run_record = runtime.get_run(run_id)
  if run_record.isNil:
    return false
  if run_record.run.state in {ArsCompleted, ArsFailed, ArsCancelled}:
    return false
  run_record.run.apply_event(AreCancel)
  true

proc parse_provider_action(response: JsonNode): string =
  if response.kind == JObject and response.hasKey("action") and response["action"].kind == JString:
    response["action"].getStr().toLowerAscii()
  else:
    ""

proc get_provider_text(response: JsonNode): string =
  if response.kind == JObject and response.hasKey("message") and response["message"].kind == JString:
    response["message"].getStr()
  else:
    ""

proc get_provider_tool(response: JsonNode): string =
  if response.kind == JObject and response.hasKey("tool") and response["tool"].kind == JString:
    response["tool"].getStr()
  else:
    ""

proc get_provider_args(response: JsonNode): JsonNode =
  if response.kind == JObject and response.hasKey("args") and response["args"].kind == JObject:
    response["args"]
  else:
    newJObject()

proc fail_run(run_record: AgentRunRecord; message: string; provider_response = newJNull(); tool_result = newJNull()): AgentStepResult =
  run_record.run.apply_event(AreFail, message)
  run_record.add_history(%*{"type": "error", "message": message})
  AgentStepResult(
    run_id: run_record.run.run_id,
    state: run_record.run.state,
    message: message,
    provider_response: provider_response,
    tool_result: tool_result
  )

proc step_run*(runtime: AgentRuntime; run_id: string; provider: AgentProvider): AgentStepResult =
  let run_record = runtime.get_run(run_id)
  if run_record.isNil:
    raise newException(ValueError, "Run not found: " & run_id)

  result.run_id = run_id

  if run_record.run.state in {ArsCompleted, ArsFailed, ArsCancelled}:
    result.state = run_record.run.state
    result.message = if run_record.final_output.len > 0: run_record.final_output else: run_record.run.error_message
    result.provider_response = newJNull()
    result.tool_result = newJNull()
    return

  if provider == nil:
    result = fail_run(run_record, "provider is nil")
    return

  if run_record.run.state == ArsQueued:
    run_record.run.apply_event(AreStart)

  if run_record.step_count >= run_record.config.max_steps:
    result = fail_run(run_record, "max_steps exceeded")
    return

  inc run_record.step_count

  let response = provider(run_id, run_record.envelope, run_record.history)
  run_record.add_history(%*{"type": "provider", "response": response})
  result.provider_response = response

  let action = parse_provider_action(response)
  case action
  of "final":
    let message = get_provider_text(response)
    run_record.final_output = message
    run_record.run.apply_event(AreComplete)
    result.state = run_record.run.state
    result.message = message
    result.tool_result = newJNull()
  of "tool":
    if runtime.tool_registry.isNil:
      result = fail_run(run_record, "tool registry is nil", response)
      return

    if run_record.tool_call_count >= run_record.config.max_tool_calls:
      result = fail_run(run_record, "max_tool_calls exceeded", response)
      return

    run_record.run.apply_event(AreWaitTool)

    let tool_name = get_provider_tool(response)
    if tool_name.len == 0:
      result = fail_run(run_record, "provider tool action missing tool name", response)
      return

    let tool_args = get_provider_args(response)
    let tool_ctx = new_tool_context(
      run_id = run_id,
      workspace_id = run_record.envelope.workspace_id,
      user_id = run_record.envelope.user_id
    )

    let tool_result = runtime.tool_registry.invoke_tool(tool_ctx, tool_name, tool_args)
    inc run_record.tool_call_count
    run_record.add_history(%*{
      "type": "tool",
      "name": tool_name,
      "args": tool_args,
      "result": tool_result
    })

    result.tool_result = tool_result

    if tool_result.kind == JObject and tool_result.hasKey("ok") and tool_result["ok"].kind == JBool and tool_result["ok"].getBool():
      run_record.run.apply_event(AreToolResult)
      result.state = run_record.run.state
      result.message = "tool executed"
    else:
      let err_msg =
        if tool_result.kind == JObject and tool_result.hasKey("error") and tool_result["error"].kind == JString:
          tool_result["error"].getStr()
        else:
          "tool execution failed"
      result = fail_run(run_record, err_msg, response, tool_result)
  else:
    result = fail_run(run_record, "unsupported provider action: " & action, response)

proc run_until_terminal*(runtime: AgentRuntime; run_id: string; provider: AgentProvider): AgentStepResult =
  while true:
    let step = runtime.step_run(run_id, provider)
    result = step
    if step.state in {ArsCompleted, ArsFailed, ArsCancelled}:
      return
