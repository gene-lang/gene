import unittest
import std/json

import ../src/genex/ai/control_slack
import ../src/genex/ai/utils

suite "Slack control adapter":
  test "signature verify accepts valid signature":
    let secret = "slack-secret"
    let body = "{\"type\":\"event_callback\",\"event_id\":\"Ev1\"}"
    let ts = "1700000000"
    let sig = compute_slack_signature(secret, ts, body)

    let result = verify_slack_signature(
      signing_secret = secret,
      timestamp_sec = ts,
      provided_signature = sig,
      raw_body = body,
      now_ms = 1700000000'i64 * 1000,
      max_skew_sec = 300
    )

    check result.ok

  test "signature verify rejects mismatch and stale timestamp":
    let bad_sig = verify_slack_signature(
      signing_secret = "s",
      timestamp_sec = "1700000000",
      provided_signature = "v0=deadbeef",
      raw_body = "{}",
      now_ms = 1700000000'i64 * 1000,
      max_skew_sec = 300
    )
    check not bad_sig.ok

    let stale = verify_slack_signature(
      signing_secret = "s",
      timestamp_sec = "1690000000",
      provided_signature = compute_slack_signature("s", "1690000000", "{}"),
      raw_body = "{}",
      now_ms = 1700000000'i64 * 1000,
      max_skew_sec = 300
    )
    check not stale.ok
    check stale.reason == "stale timestamp"

  test "url verification helpers":
    let payload = %*{"type": "url_verification", "challenge": "abc123"}
    check is_slack_url_verification(payload)
    check slack_url_challenge(payload) == "abc123"

  test "event callback maps to CommandEnvelope":
    let payload = %*{
      "type": "event_callback",
      "team_id": "T123",
      "event_id": "Ev123",
      "event_time": 1700000000,
      "event": {
        "type": "message",
        "user": "U123",
        "text": "run build",
        "channel": "C123",
        "ts": "1700000000.001",
        "thread_ts": "1700000000.000"
      }
    }

    let cmd = slack_event_to_command(payload)
    check cmd.source == CsSlack
    check cmd.command_id == "Ev123"
    check cmd.workspace_id == "T123"
    check cmd.user_id == "U123"
    check cmd.channel_id == "C123"
    check cmd.thread_id == "1700000000.000"
    check cmd.text == "run build"
    check cmd.metadata["event_type"].getStr() == "message"

  test "bot messages are ignored":
    let payload = %*{
      "type": "event_callback",
      "event_id": "EvBot",
      "event": {
        "type": "message",
        "bot_id": "B123",
        "text": "ignored",
        "channel": "C123"
      }
    }

    expect(ValueError):
      discard slack_event_to_command(payload)

  test "replay guard deduplicates event ids":
    let guard = new_slack_replay_guard(ttl_sec = 10)
    check not guard.mark_or_is_duplicate("Ev1", now_ms = 1000)
    check guard.mark_or_is_duplicate("Ev1", now_ms = 2000)

    # After ttl, event id is expired and can be accepted again.
    guard.cleanup_replay_guard(now_ms = 12000)
    check not guard.mark_or_is_duplicate("Ev1", now_ms = 12000)
