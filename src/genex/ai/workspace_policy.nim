## Workspace-scoped access policy for tool execution.
## Prevents cross-workspace data/tool access, enforces per-workspace
## tool allowlists, and redacts secrets from audit logs.

import std/json
import std/tables
import std/strutils

import ./tools


type
  WorkspacePermission* = object
    workspace_id*: string
    allowed_tools*: seq[string]       ## Empty = all tools allowed
    denied_tools*: seq[string]        ## Explicit denials override allowed
    filesystem_roots*: seq[string]    ## Allowed filesystem roots
    shell_allowlist*: seq[string]     ## Allowed shell commands
    max_tool_calls_per_run*: int      ## 0 = unlimited

  WorkspacePolicyEngine* = ref object
    permissions*: Table[string, WorkspacePermission]
    default_denied_tools*: seq[string]
    secret_patterns*: seq[string]


proc new_workspace_policy_engine*(): WorkspacePolicyEngine =
  WorkspacePolicyEngine(
    permissions: initTable[string, WorkspacePermission](),
    default_denied_tools: @[],
    secret_patterns: @["password", "secret", "token", "api_key", "apikey",
                        "private_key", "access_key", "credential"]
  )

proc set_workspace_permission*(engine: WorkspacePolicyEngine;
                               perm: WorkspacePermission) =
  if engine.isNil:
    return
  if perm.workspace_id.len == 0:
    raise newException(ValueError, "workspace_id cannot be empty")
  engine.permissions[perm.workspace_id] = perm

proc get_workspace_permission*(engine: WorkspacePolicyEngine;
                               workspace_id: string): WorkspacePermission =
  if engine.isNil or not engine.permissions.hasKey(workspace_id):
    return WorkspacePermission(workspace_id: workspace_id)
  engine.permissions[workspace_id]


# --- Policy decision proc compatible with ToolPolicy ---

proc workspace_policy_check*(engine: WorkspacePolicyEngine;
                             ctx: ToolContext; tool_name: string;
                             args: JsonNode): ToolPolicyDecision =
  ## Check if the tool invocation is allowed for the given context.
  if engine.isNil:
    return allow_decision()

  let ws_id = ctx.workspace_id
  if ws_id.len == 0:
    return deny_decision("missing workspace_id in context")

  let norm_tool = tool_name.strip().toLowerAscii()

  # Check default denials
  for denied in engine.default_denied_tools:
    if norm_tool == denied.toLowerAscii():
      return deny_decision("tool '" & tool_name & "' is globally denied")

  # Check workspace-specific permissions if configured
  if engine.permissions.hasKey(ws_id):
    let perm = engine.permissions[ws_id]

    # Explicit denials
    for denied in perm.denied_tools:
      if norm_tool == denied.toLowerAscii():
        return deny_decision("tool '" & tool_name & "' denied for workspace " & ws_id)

    # Allowed tools (if non-empty, only listed tools are allowed)
    if perm.allowed_tools.len > 0:
      var found = false
      for allowed in perm.allowed_tools:
        if norm_tool == allowed.toLowerAscii():
          found = true
          break
      if not found:
        return deny_decision("tool '" & tool_name & "' not in workspace allowlist")

    # Filesystem root validation
    if norm_tool == "filesystem" and perm.filesystem_roots.len > 0:
      if args.kind == JObject and args.hasKey("path"):
        let path = args["path"].getStr("")
        if path.len > 0:
          var in_root = false
          for root in perm.filesystem_roots:
            if path.startsWith(root):
              in_root = true
              break
          if not in_root:
            return deny_decision("path '" & path & "' outside allowed roots for workspace " & ws_id)

    # Shell command validation
    if norm_tool == "shell" and perm.shell_allowlist.len > 0:
      if args.kind == JObject and args.hasKey("argv") and args["argv"].kind == JArray:
        let argv = args["argv"]
        if argv.len > 0 and argv[0].kind == JString:
          let cmd = argv[0].getStr("")
          if cmd notin perm.shell_allowlist:
            return deny_decision("command '" & cmd & "' not in workspace shell allowlist")

  allow_decision()

proc make_tool_policy*(engine: WorkspacePolicyEngine): ToolPolicy =
  ## Create a ToolPolicy closure from this engine.
  result = proc(ctx: ToolContext; tool_name: string; args: JsonNode): ToolPolicyDecision {.gcsafe.} =
    engine.workspace_policy_check(ctx, tool_name, args)


# --- Secret redaction ---

proc redact_secrets*(engine: WorkspacePolicyEngine; text: string): string =
  ## Redact values that look like secrets from log/audit text.
  ## Simple pattern: redacts values after known key patterns in JSON-like strings.
  result = text
  for pattern in engine.secret_patterns:
    # Redact patterns like "key":"value" or "key": "value"
    var i = result.find(pattern)
    while i >= 0:
      # Find the next quoted value after this pattern
      let colon_pos = result.find(':', i + pattern.len)
      if colon_pos >= 0:
        let quote_start = result.find('"', colon_pos)
        if quote_start >= 0 and quote_start - colon_pos <= 3:
          let quote_end = result.find('"', quote_start + 1)
          if quote_end > quote_start:
            result = result[0..quote_start] & "***REDACTED***" & result[quote_end..^1]
      let next_i = result.find(pattern, i + 1)
      if next_i <= i:
        break
      i = next_i

proc redact_audit_event*(engine: WorkspacePolicyEngine;
                         event: ToolAuditEvent): ToolAuditEvent =
  ## Return a copy of the audit event with secrets redacted in args/result JSON.
  result = event
  if not engine.isNil:
    if not event.args_json.isNil:
      result.args_json =
        try: parseJson(engine.redact_secrets($event.args_json))
        except: event.args_json
    if not event.result_json.isNil:
      result.result_json =
        try: parseJson(engine.redact_secrets($event.result_json))
        except: event.result_json
