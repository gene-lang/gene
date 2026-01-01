## Why

Gene needs a demonstrable end-to-end application showcasing its HTTP server capabilities and LLM integration. A chat interface provides a compelling, interactive demo that validates both the REST API infrastructure and llama.cpp bindings.

## What Changes

- Add a React frontend application for chat UI
- Create Gene REST API endpoints for chat functionality
- Integrate with existing llama.cpp bindings in genex/llm.nim
- Provide example configuration for local model loading

## Impact

- Affected specs: New `llm-chat` capability
- Affected code:
  - `example-projects/llm_app/backend/` - Gene HTTP server with chat endpoints
  - `example-projects/llm_app/frontend/` - React frontend application
  - Documentation updates for running the demo

## Directory Structure

```
example-projects/llm_app/
├── frontend/          # React app (Vite)
│   ├── package.json
│   ├── src/
│   └── ...
└── backend/
    ├── package.gene   # Gene package manifest
    └── src/
        └── main.gene  # Server entry point
```
