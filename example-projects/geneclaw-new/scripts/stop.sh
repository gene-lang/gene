#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"

ENV_FILE="${GENECLAW_ENV_FILE:-$PROJECT_ROOT/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
elif [[ -f "$PROJECT_ROOT/.env.example" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/.env.example"
  set +a
fi

GENECLAW_NEW_HOME="${GENECLAW_NEW_HOME:-$PROJECT_ROOT/home}"
GENECLAW_DAEMON_DIR="${GENECLAW_DAEMON_DIR:-$GENECLAW_NEW_HOME/daemon}"
GENECLAW_PID_FILE="${GENECLAW_PID_FILE:-$GENECLAW_DAEMON_DIR/geneclaw-new.pid}"
GENECLAW_LOG_FILE="${GENECLAW_LOG_FILE:-$GENECLAW_DAEMON_DIR/geneclaw-new.log}"

if [[ ! -f "$GENECLAW_PID_FILE" ]]; then
  echo "geneclaw-new is not running (no pid file at $GENECLAW_PID_FILE)"
  exit 0
fi

daemon_pid="$(tr -d '[:space:]' < "$GENECLAW_PID_FILE")"
if [[ -z "$daemon_pid" ]]; then
  rm -f "$GENECLAW_PID_FILE"
  echo "geneclaw-new is not running (empty pid file removed)"
  exit 0
fi

if ! kill -0 "$daemon_pid" 2>/dev/null; then
  rm -f "$GENECLAW_PID_FILE"
  echo "geneclaw-new is not running (stale pid $daemon_pid removed)"
  exit 0
fi

kill "$daemon_pid" 2>/dev/null || true

deadline=$((SECONDS + 10))
while kill -0 "$daemon_pid" 2>/dev/null; do
  if (( SECONDS >= deadline )); then
    kill -KILL "$daemon_pid" 2>/dev/null || true
    break
  fi
  sleep 0.2
done

rm -f "$GENECLAW_PID_FILE"
printf '%s geneclaw-new daemon stopped\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$GENECLAW_LOG_FILE"

echo "geneclaw-new stopped (pid $daemon_pid)"
echo "log: $GENECLAW_LOG_FILE"
