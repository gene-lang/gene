#!/usr/bin/env bash

set -euo pipefail

REQUESTS="${REQUESTS:-20}"
CONCURRENCY="${CONCURRENCY:-10}"
SERVER_PIDS=()
SERVER_LOGS=()

cleanup() {
  local pid
  for pid in "${SERVER_PIDS[@]:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    fi
  done

  if [[ ${#SERVER_LOGS[@]} -gt 0 ]]; then
    echo
    echo "server logs:"
    printf '  %s\n' "${SERVER_LOGS[@]}"
  fi
}
trap cleanup EXIT

wait_for_server() {
  local url="$1"
  local log_file="$2"
  local attempt

  for attempt in $(seq 1 50); do
    if curl -fsS "${url}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  echo "server did not become ready: ${url}" >&2
  tail -n 50 "${log_file}" >&2 || true
  return 1
}

start_server() {
  local example="$1"
  local port="$2"
  local log_file
  log_file="$(mktemp -t gene-http-ab-demo.XXXXXX.log)"

  /usr/bin/script -q "${log_file}" ./bin/gene run "${example}" >/dev/null 2>&1 &
  local server_pid=$!
  SERVER_PIDS+=("${server_pid}")
  SERVER_LOGS+=("${log_file}")

  local url="http://127.0.0.1:${port}"
  wait_for_server "${url}" "${log_file}"
  printf '%s\n' "${url}"
}

run_ab() {
  local label="$1"
  local url="$2"

  echo "== ${label} =="
  echo "server: ${url}"
  echo "requests: ${REQUESTS}"
  echo "concurrency: ${CONCURRENCY}"
  echo "endpoint: /slow"
  echo

  echo "-- sequential --"
  ab -n "${REQUESTS}" -c 1 "${url}/slow"
  echo
  echo "-- concurrent --"
  ab -n "${REQUESTS}" -c "${CONCURRENCY}" "${url}/slow"
  echo
}

BASELINE_URL="$(start_server "examples/http_ab_demo.gene" 8088)"
run_ab "blocking baseline" "${BASELINE_URL}"

ACTOR_URL="$(start_server "examples/http_ab_actor_demo.gene" 8089)"
run_ab "actor-backed concurrent server" "${ACTOR_URL}"
