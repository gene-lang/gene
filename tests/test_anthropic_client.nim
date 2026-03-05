import unittest, json, tables, os

import ../src/genex/ai/anthropic_client

suite "Anthropic Client":
  test "auth token takes precedence over api token":
    let cfg = buildAnthropicConfig(%*{
      "api_token": "sk-ant-api-123",
      "auth_token": "sk-ant-oat-xyz"
    })
    check cfg.auth_token == "sk-ant-oat-xyz"
    check cfg.headers.hasKey("Authorization")
    check cfg.headers["Authorization"] == "Bearer sk-ant-oat-xyz"
    check not cfg.headers.hasKey("x-api-key")

  test "oauth token prefix in api_token is auto-detected":
    let cfg = buildAnthropicConfig(%*{
      "api_token": "sk-ant-oat-from-api-token"
    })
    check cfg.auth_token == "sk-ant-oat-from-api-token"
    check cfg.headers.hasKey("Authorization")
    check not cfg.headers.hasKey("x-api-key")

  test "api token mode uses x-api-key header":
    let cfg = buildAnthropicConfig(%*{
      "api_token": "sk-ant-api-only",
      "anthropic_version": "2023-06-01"
    })
    check cfg.headers.hasKey("x-api-key")
    check cfg.headers["x-api-key"] == "sk-ant-api-only"
    check not cfg.headers.hasKey("Authorization")
    check cfg.headers["anthropic-version"] == "2023-06-01"

  test "env var resolution prefers ANTHROPIC_OAUTH_TOKEN over ANTHROPIC_API_KEY":
    let had_api = existsEnv("ANTHROPIC_API_KEY")
    let had_oauth = existsEnv("ANTHROPIC_OAUTH_TOKEN")
    let old_api = getEnv("ANTHROPIC_API_KEY")
    let old_oauth = getEnv("ANTHROPIC_OAUTH_TOKEN")
    try:
      putEnv("ANTHROPIC_API_KEY", "sk-ant-api-env")
      putEnv("ANTHROPIC_OAUTH_TOKEN", "sk-ant-oat-env")
      let cfg = buildAnthropicConfig()
      check cfg.auth_token == "sk-ant-oat-env"
      check cfg.headers.hasKey("Authorization")
      check not cfg.headers.hasKey("x-api-key")
    finally:
      if had_api:
        putEnv("ANTHROPIC_API_KEY", old_api)
      else:
        delEnv("ANTHROPIC_API_KEY")
      if had_oauth:
        putEnv("ANTHROPIC_OAUTH_TOKEN", old_oauth)
      else:
        delEnv("ANTHROPIC_OAUTH_TOKEN")

  test "messages payload merges required and optional fields":
    let cfg = buildAnthropicConfig(%*{
      "api_token": "sk-ant-api-123",
      "model": "claude-3-5-haiku-latest"
    })
    let payload = buildAnthropicMessagesPayload(cfg, %*{
      "messages": [{"role": "user", "content": "hello"}],
      "max_tokens": 42,
      "temperature": 0.2,
      "system": "You are helpful."
    })
    check payload["model"].getStr() == "claude-3-5-haiku-latest"
    check payload["max_tokens"].getInt() == 42
    check payload["temperature"].getFloat() == 0.2
    check payload["system"].getStr() == "You are helpful."
    check payload["messages"].kind == JArray
    check payload["messages"].len == 1
