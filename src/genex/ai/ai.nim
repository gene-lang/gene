## Main module for genex/ai - OpenAI-compatible API wrapper
## Exports all OpenAI functionality to Gene

import bindings, openai_client, streaming
import ../../gene/vm
import ../../gene/types

# Export the native functions that will be registered with the VM
export vm_openai_new_client
export vm_openai_chat
export vm_openai_embeddings
export vm_openai_respond
export vm_openai_stream

# Export types and utilities
export OpenAIConfig, OpenAIError, StreamingChunk, StreamEvent
export buildOpenAIConfig, geneValueToJson, jsonToGeneValue
export buildChatPayload, buildEmbeddingsPayload, buildResponsesPayload
export redactSecret, getEnvVar

# Module initialization function
proc init_ai_module*() =
  # This will be called from the VM initialization
  # Register all native functions here
  discard

when isMainModule:
  # Test the module directly if run as a script
  echo "OpenAI API module loaded successfully"