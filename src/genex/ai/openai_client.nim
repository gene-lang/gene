## OpenAI-Compatible API Client for Gene
## Implements the OpenAIClient class with support for chat completions, responses, embeddings, and streaming

import json, httpclient, strutils, os, tables

type
  OpenAIConfig* = ref object
    api_key*: string
    base_url*: string
    model*: string
    organization*: string
    headers*: Table[string, string]
    timeout_ms*: int
    max_retries*: int
    extra*: JsonNode

  OpenAIError* = ref object of CatchableError
    status*: int
    provider_error*: string
    request_id*: string
    retry_after*: int
    metadata*: JsonNode

  StreamingChunk* = ref object
    delta*: JsonNode
    done*: bool
    event*: string

# Constants for OpenAI API endpoints
const
  DEFAULT_BASE_URL* = "https://api.openai.com/v1"
  DEFAULT_TIMEOUT_MS* = 30000
  DEFAULT_MAX_RETRIES* = 3

# Helper functions for environment variable reading
proc getEnvVar*(key: string, default: string = ""): string =
  try:
    result = os.getEnv(key, default)
  except:
    result = default

# Secret redaction for logging
proc redactSecret*(value: string): string =
  if value.len <= 8:
    return "*".repeat(value.len)
  result = value[0..2] & "*".repeat(value.len - 6) & value[value.len-3..value.len-1]

# Config building with precedence: options > env > defaults
proc buildOpenAIConfig*(options: JsonNode = newJNull()): OpenAIConfig =
  let opts = if options.kind != JNull: options else: %*{}

  result = OpenAIConfig(
    api_key: if opts.hasKey("api_key"): opts["api_key"].getStr(getEnvVar("OPENAI_API_KEY")) else: getEnvVar("OPENAI_API_KEY"),
    base_url: if opts.hasKey("base_url"): opts["base_url"].getStr(getEnvVar("OPENAI_BASE_URL", DEFAULT_BASE_URL)) else: getEnvVar("OPENAI_BASE_URL", DEFAULT_BASE_URL),
    model: if opts.hasKey("model"): opts["model"].getStr("gpt-3.5-turbo") else: "gpt-3.5-turbo",
    organization: if opts.hasKey("organization"): opts["organization"].getStr(getEnvVar("OPENAI_ORG")) else: getEnvVar("OPENAI_ORG"),
    timeout_ms: if opts.hasKey("timeout_ms"): opts["timeout_ms"].getInt(DEFAULT_TIMEOUT_MS) else: DEFAULT_TIMEOUT_MS,
    max_retries: if opts.hasKey("max_retries"): opts["max_retries"].getInt(DEFAULT_MAX_RETRIES) else: DEFAULT_MAX_RETRIES,
    headers: initTable[string, string]()
  )

  # Add default headers
  result.headers["Content-Type"] = "application/json"
  result.headers["User-Agent"] = "gene-openai-client/1.0"

  if result.api_key != "":
    result.headers["Authorization"] = "Bearer " & result.api_key

  if result.organization != "":
    result.headers["OpenAI-Organization"] = result.organization

  # Merge custom headers from options
  if opts.hasKey("headers"):
    let headers = opts["headers"]
    for key, value in headers:
      result.headers[key] = value.getStr()

  # Store extra fields for provider-specific passthrough
  if opts.hasKey("extra"):
    result.extra = opts["extra"]
  else:
    result.extra = %*{}

# HTTP client wrapper with signing and error handling
proc performRequest*(config: OpenAIConfig, httpMethod: string, endpoint: string,
                   payload: JsonNode = newJNull(), streaming: bool = false): JsonNode =
  var client = newHttpClient(timeout = config.timeout_ms)

  try:
    let url = config.base_url & endpoint
    let body = if payload.kind != JNull: $payload else: ""

    var headers = newHttpHeaders()
    for key, value in config.headers:
      headers[key] = value

    when defined(debug):
      echo "DEBUG: OpenAI API Request: ", httpMethod, " ", url
      echo "DEBUG: Headers: ", headers
      if body != "":
        echo "DEBUG: Body: ", body[0..min(body.len, 200)] & (if body.len > 200: "..." else: "")

    let response = client.request(url, httpMethod = case httpMethod.toUpperAscii():
      of "GET": HttpGet
      of "POST": HttpPost
      of "PUT": HttpPut
      of "DELETE": HttpDelete
      of "HEAD": HttpHead
      of "PATCH": HttpPatch
      of "OPTIONS": HttpOptions
      else: HttpPost,  # Default to POST for OpenAI APIs
      body = body, headers = headers)

    when defined(debug):
      echo "DEBUG: Response status: ", response.status
      echo "DEBUG: Response headers: ", response.headers

    let statusCode = response.status.split()[0]  # Extract just the status code (e.g., "200" from "200 OK")
    if statusCode != "200":
      let errorBody = try: parseJson(response.body) except: %*{"message": response.body}
      var errorMsg = ""
      var errorType = ""
      if errorBody.hasKey("error"):
        if errorBody["error"].hasKey("message"):
          errorMsg = errorBody["error"]["message"].getStr()
        if errorBody["error"].hasKey("type"):
          errorType = errorBody["error"]["type"].getStr()
      else:
        errorMsg = errorBody.getStr()

      var error = OpenAIError(
        msg: "OpenAI API Error: " & errorMsg,
        status: parseInt(statusCode),
        provider_error: errorType
      )

      # Extract request ID if available
      if response.headers.hasKey("x-request-id"):
        error.request_id = response.headers["x-request-id"]

      # Extract retry-after for rate limiting
      if statusCode == "429" and response.headers.hasKey("retry-after"):
        try:
          error.retry_after = parseInt(response.headers["retry-after"])
        except:
          discard

      raise error

    if not streaming:
      result = parseJson(response.body)
    else:
      # For streaming, we'll handle the response body differently
      result = %*{"streaming": true, "body": response.body}

  except OpenAIError:
    raise
  except Exception as e:
    raise OpenAIError(
      msg: "Network error: " & e.msg,
      status: -1,
      provider_error: "network"
    )
  finally:
    client.close()

# Payload builders for different endpoints
proc buildChatPayload*(config: OpenAIConfig, options: JsonNode): JsonNode =
  var payload = %*{
    "model": if options.hasKey("model"): options["model"].getStr(config.model) else: config.model,
    "messages": if options.hasKey("messages"): options["messages"] else: %*[],
    "max_tokens": if options.hasKey("max_tokens"): options["max_tokens"].getInt(1000) else: 1000,
    "temperature": if options.hasKey("temperature"): options["temperature"].getFloat(1.0) else: 1.0,
    "stream": if options.hasKey("stream"): options["stream"].getBool(false) else: false
  }

  # Merge optional parameters
  let optionalFields = ["top_p", "n", "stop", "presence_penalty", "frequency_penalty", "logit_bias", "user"]
  for field in optionalFields:
    if options.hasKey(field):
      payload[field] = options[field]

  # Add extra fields from config
  if config.extra != nil:
    for key, value in config.extra:
      payload[key] = value

  return payload

proc buildEmbeddingsPayload*(config: OpenAIConfig, options: JsonNode): JsonNode =
  var payload = %*{
    "model": if options.hasKey("model"): options["model"].getStr(config.model) else: config.model,
    "input": if options.hasKey("input"): options["input"] else: %*"",
    "encoding_format": if options.hasKey("encoding_format"): options["encoding_format"].getStr("float") else: "float"
  }

  # Add extra fields from config
  if config.extra != nil:
    for key, value in config.extra:
      payload[key] = value

  return payload

proc buildResponsesPayload*(config: OpenAIConfig, options: JsonNode): JsonNode =
  var payload = %*{
    "model": if options.hasKey("model"): options["model"].getStr(config.model) else: config.model,
    "input": if options.hasKey("input"): options["input"] else: %*"",
    "max_tokens": if options.hasKey("max_tokens"): options["max_tokens"].getInt(1000) else: 1000,
    "temperature": if options.hasKey("temperature"): options["temperature"].getFloat(1.0) else: 1.0
  }

  # Merge optional parameters
  let optionalFields = ["top_p", "n", "stop", "presence_penalty", "frequency_penalty", "tools", "tool_choice"]
  for field in optionalFields:
    if options.hasKey(field):
      payload[field] = options[field]

  # Add extra fields from config
  if config.extra != nil:
    for key, value in config.extra:
      payload[key] = value

  return payload

# Response normalization from JSON to Gene values
proc normalizeResponse*(response: JsonNode): JsonNode =
  # Convert JSON response to maintain consistency with Gene's Value types
  # This is a placeholder - actual conversion will be handled in the Gene bridge
  result = response