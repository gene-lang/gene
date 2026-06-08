#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "$PROJECT_ROOT/../.." >/dev/null 2>&1 && pwd)"

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

GENE_BIN="${GENE_BIN:-$REPO_ROOT/bin/gene}"
GENECLAW_NEW_HOME="${GENECLAW_NEW_HOME:-$PROJECT_ROOT/home}"
GENECLAW_DAEMON_INTERVAL_SECONDS="${GENECLAW_DAEMON_INTERVAL_SECONDS:-5}"
GENECLAW_DAEMON_DIR="${GENECLAW_DAEMON_DIR:-$GENECLAW_NEW_HOME/daemon}"
GENECLAW_PID_FILE="${GENECLAW_PID_FILE:-$GENECLAW_DAEMON_DIR/geneclaw-new.pid}"
GENECLAW_LOG_FILE="${GENECLAW_LOG_FILE:-$GENECLAW_DAEMON_DIR/geneclaw-new.log}"

if [[ ! -x "$GENE_BIN" ]]; then
  echo "gene binary not found or not executable: $GENE_BIN" >&2
  exit 1
fi

mkdir -p "$GENECLAW_NEW_HOME" "$GENECLAW_DAEMON_DIR"

if [[ -f "$GENECLAW_PID_FILE" ]]; then
  existing_pid="$(tr -d '[:space:]' < "$GENECLAW_PID_FILE")"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    echo "geneclaw-new already running (pid $existing_pid)"
    echo "log: $GENECLAW_LOG_FILE"
    exit 0
  fi
  rm -f "$GENECLAW_PID_FILE"
fi

(
  cd "$PROJECT_ROOT"
  trap 'exit 0' INT TERM
  printf '%s geneclaw-new daemon starting\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$GENECLAW_LOG_FILE"
  while :; do
    "$GENE_BIN" run src/main.gene schedule run-due >> "$GENECLAW_LOG_FILE" 2>&1 || {
      status="$?"
      printf '%s scheduler dispatch failed with exit code %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$status" >> "$GENECLAW_LOG_FILE"
    }
    sleep "$GENECLAW_DAEMON_INTERVAL_SECONDS" &
    wait "$!" || exit 0
  done
) &

daemon_pid="$!"
printf '%s\n' "$daemon_pid" > "$GENECLAW_PID_FILE"

echo "geneclaw-new started (pid $daemon_pid)"
echo "home: $GENECLAW_NEW_HOME"
echo "log: $GENECLAW_LOG_FILE"
echo "stop: $PROJECT_ROOT/scripts/stop.sh"
