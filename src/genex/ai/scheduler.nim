import std/tables
import std/json
import std/os
import std/strutils

import ./utils


type
  ScheduleJobState* = enum
    SjsActive
    SjsPaused
    SjsCancelled
    SjsDeadLetter

  RetryPolicy* = object
    max_retries*: int
    backoff_ms*: int64

  ScheduleJob* = object
    job_id*: string
    workspace_id*: string
    payload*: JsonNode
    next_run_ms*: int64
    interval_ms*: int64
    state*: ScheduleJobState
    retry_count*: int
    retry_policy*: RetryPolicy
    last_error*: string
    last_run_ms*: int64

  SchedulerStore* = ref object
    path*: string
    jobs*: Table[string, ScheduleJob]


proc state_to_string(state: ScheduleJobState): string =
  case state
  of SjsActive: "active"
  of SjsPaused: "paused"
  of SjsCancelled: "cancelled"
  of SjsDeadLetter: "deadletter"

proc parse_state(s: string): ScheduleJobState =
  case s.toLowerAscii()
  of "active": SjsActive
  of "paused": SjsPaused
  of "cancelled": SjsCancelled
  of "deadletter": SjsDeadLetter
  else: SjsActive

proc job_to_json(job: ScheduleJob): JsonNode =
  %*{
    "job_id": job.job_id,
    "workspace_id": job.workspace_id,
    "payload": if job.payload.isNil: newJObject() else: job.payload,
    "next_run_ms": job.next_run_ms,
    "interval_ms": job.interval_ms,
    "state": state_to_string(job.state),
    "retry_count": job.retry_count,
    "retry_policy": {
      "max_retries": job.retry_policy.max_retries,
      "backoff_ms": job.retry_policy.backoff_ms
    },
    "last_error": job.last_error,
    "last_run_ms": job.last_run_ms
  }

proc get_json_str(node: JsonNode; key: string): string =
  if node.kind == JObject and node.hasKey(key) and node[key].kind == JString:
    node[key].getStr()
  else:
    ""

proc get_json_int64(node: JsonNode; key: string): int64 =
  if node.kind == JObject and node.hasKey(key) and node[key].kind in {JInt, JFloat}:
    node[key].getInt().int64
  else:
    0'i64

proc get_json_int(node: JsonNode; key: string): int =
  if node.kind == JObject and node.hasKey(key) and node[key].kind in {JInt, JFloat}:
    node[key].getInt()
  else:
    0

proc job_from_json(node: JsonNode): ScheduleJob =
  if node.kind != JObject:
    raise newException(ValueError, "ScheduleJob JSON must be object")

  result.job_id = get_json_str(node, "job_id")
  result.workspace_id = get_json_str(node, "workspace_id")
  result.payload =
    if node.hasKey("payload") and node["payload"].kind == JObject:
      node["payload"]
    else:
      newJObject()
  result.next_run_ms = get_json_int64(node, "next_run_ms")
  result.interval_ms = get_json_int64(node, "interval_ms")
  result.state = parse_state(get_json_str(node, "state"))
  result.retry_count = get_json_int(node, "retry_count")
  result.last_error = get_json_str(node, "last_error")
  result.last_run_ms = get_json_int64(node, "last_run_ms")

  if node.hasKey("retry_policy") and node["retry_policy"].kind == JObject:
    result.retry_policy = RetryPolicy(
      max_retries: get_json_int(node["retry_policy"], "max_retries"),
      backoff_ms: get_json_int64(node["retry_policy"], "backoff_ms")
    )
  else:
    result.retry_policy = RetryPolicy(max_retries: 3, backoff_ms: 5000)

proc save_store(store: SchedulerStore) =
  if store.isNil or store.path.len == 0:
    return

  var arr = newJArray()
  for _, job in store.jobs:
    arr.add(job_to_json(job))
  writeFile(store.path, $arr)

proc load_store(path: string): Table[string, ScheduleJob] =
  result = initTable[string, ScheduleJob]()
  if path.len == 0 or not fileExists(path):
    return

  let raw = readFile(path)
  if raw.strip().len == 0:
    return

  let parsed = parseJson(raw)
  if parsed.kind != JArray:
    raise newException(ValueError, "Scheduler store file must contain JSON array")

  for item in parsed.items:
    let job = job_from_json(item)
    if job.job_id.len > 0:
      result[job.job_id] = job

proc new_scheduler_store*(path = ""): SchedulerStore =
  SchedulerStore(
    path: path,
    jobs: load_store(path)
  )

proc get_job*(store: SchedulerStore; job_id: string): ScheduleJob =
  if store.isNil or job_id.len == 0:
    return ScheduleJob()
  store.jobs.getOrDefault(job_id, ScheduleJob())

proc list_jobs*(store: SchedulerStore): seq[ScheduleJob] =
  if store.isNil:
    return @[]
  for _, job in store.jobs:
    result.add(job)

proc create_interval_job*(
  store: SchedulerStore;
  job_id: string;
  workspace_id: string;
  payload: JsonNode;
  interval_ms: int64;
  first_run_ms: int64;
  retry_policy = RetryPolicy(max_retries: 3, backoff_ms: 5000)
): ScheduleJob =
  if store.isNil:
    raise newException(ValueError, "SchedulerStore is nil")
  if job_id.len == 0:
    raise newException(ValueError, "job_id cannot be empty")
  if interval_ms <= 0:
    raise newException(ValueError, "interval_ms must be > 0")

  let job = ScheduleJob(
    job_id: job_id,
    workspace_id: workspace_id,
    payload: if payload.isNil: newJObject() else: payload,
    next_run_ms: first_run_ms,
    interval_ms: interval_ms,
    state: SjsActive,
    retry_count: 0,
    retry_policy: retry_policy,
    last_error: "",
    last_run_ms: 0
  )

  store.jobs[job_id] = job
  save_store(store)
  job

proc pause_job*(store: SchedulerStore; job_id: string): bool =
  if store.isNil or not store.jobs.hasKey(job_id):
    return false
  var job = store.jobs[job_id]
  if job.state in {SjsCancelled, SjsDeadLetter}:
    return false
  job.state = SjsPaused
  store.jobs[job_id] = job
  save_store(store)
  true

proc resume_job*(store: SchedulerStore; job_id: string): bool =
  if store.isNil or not store.jobs.hasKey(job_id):
    return false
  var job = store.jobs[job_id]
  if job.state != SjsPaused:
    return false
  job.state = SjsActive
  store.jobs[job_id] = job
  save_store(store)
  true

proc cancel_job*(store: SchedulerStore; job_id: string): bool =
  if store.isNil or not store.jobs.hasKey(job_id):
    return false
  var job = store.jobs[job_id]
  if job.state == SjsCancelled:
    return false
  job.state = SjsCancelled
  store.jobs[job_id] = job
  save_store(store)
  true

proc tick*(store: SchedulerStore; now_ms = now_unix_ms()): seq[ScheduleJob] =
  if store.isNil:
    return @[]

  var changed = false

  for job_id, job in store.jobs.mpairs:
    if job.state != SjsActive:
      continue
    if job.next_run_ms > now_ms:
      continue

    var dispatched = job
    dispatched.last_run_ms = now_ms
    result.add(dispatched)

    # Move schedule forward immediately; failure handling can override.
    job.last_run_ms = now_ms
    job.next_run_ms = now_ms + job.interval_ms
    job.last_error = ""
    job.retry_count = 0
    changed = true

  if changed:
    save_store(store)

proc mark_job_failure*(store: SchedulerStore; job_id: string; error_message: string; now_ms = now_unix_ms()): bool =
  if store.isNil or not store.jobs.hasKey(job_id):
    return false

  var job = store.jobs[job_id]
  if job.state != SjsActive:
    return false

  inc job.retry_count
  job.last_error = error_message
  job.last_run_ms = now_ms

  if job.retry_count > job.retry_policy.max_retries:
    job.state = SjsDeadLetter
  else:
    let backoff =
      if job.retry_policy.backoff_ms <= 0: 1000'i64
      else: job.retry_policy.backoff_ms
    job.next_run_ms = now_ms + backoff

  store.jobs[job_id] = job
  save_store(store)
  true

proc mark_job_success*(store: SchedulerStore; job_id: string): bool =
  if store.isNil or not store.jobs.hasKey(job_id):
    return false

  var job = store.jobs[job_id]
  if job.state != SjsActive:
    return false

  job.retry_count = 0
  job.last_error = ""
  store.jobs[job_id] = job
  save_store(store)
  true
