import std/json

import ./utils
import ./agent_runtime


type
  ProviderRoute* = object
    name*: string
    provider*: AgentProvider
    enabled*: bool

  RoutedProviderResult* = object
    ok*: bool
    provider_name*: string
    response*: JsonNode
    error_message*: string

  ProviderRouter* = ref object
    routes*: seq[ProviderRoute]


proc new_provider_router*(): ProviderRouter =
  ProviderRouter(routes: @[])

proc add_provider*(router: ProviderRouter; name: string; provider: AgentProvider; enabled = true) =
  if router.isNil:
    raise newException(ValueError, "ProviderRouter is nil")
  if name.len == 0:
    raise newException(ValueError, "provider name cannot be empty")
  if provider == nil:
    raise newException(ValueError, "provider cannot be nil")
  router.routes.add(ProviderRoute(name: name, provider: provider, enabled: enabled))

proc set_provider_enabled*(router: ProviderRouter; name: string; enabled: bool): bool =
  if router.isNil:
    return false
  for i in 0..<router.routes.len:
    if router.routes[i].name == name:
      router.routes[i].enabled = enabled
      return true
  false

proc call_with_fallback*(
  router: ProviderRouter;
  run_id: string;
  envelope: CommandEnvelope;
  history: seq[JsonNode]
): RoutedProviderResult =
  if router.isNil:
    return RoutedProviderResult(ok: false, error_message: "ProviderRouter is nil", response: newJNull())

  var last_error = ""
  for route in router.routes:
    if not route.enabled:
      continue

    try:
      let response = route.provider(run_id, envelope, history)
      if response.kind == JObject and response.hasKey("action"):
        return RoutedProviderResult(ok: true, provider_name: route.name, response: response)
      last_error = "provider '" & route.name & "' returned invalid response"
    except CatchableError as e:
      last_error = "provider '" & route.name & "' failed: " & e.msg

  RoutedProviderResult(
    ok: false,
    provider_name: "",
    response: %*{"action": "error", "message": if last_error.len > 0: last_error else: "no provider available"},
    error_message: if last_error.len > 0: last_error else: "no provider available"
  )

proc fallback_provider*(router: ProviderRouter): AgentProvider =
  result = proc(run_id: string; envelope: CommandEnvelope; history: seq[JsonNode]): JsonNode {.gcsafe.} =
    let routed = router.call_with_fallback(run_id, envelope, history)
    routed.response
