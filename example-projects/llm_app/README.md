# Gene LLM Chat App

A simple chat application demonstrating Gene's HTTP server capabilities with LLM integration.

## Architecture

```
llm_app/
├── frontend/          # React chat interface (Vite)
└── backend/           # Gene HTTP server with LLM
    ├── package.gene   # Package manifest
    ├── models/        # LLM model files
    │   └── Qwen3-14B-Q4_K_M.gguf
    └── src/
        └── main.gene  # Server entry point
```

## Prerequisites

- Gene language runtime (build with `nimble build` from gene root)
- Node.js 18+ (for frontend)
- Optional: GGUF model file for real LLM inference

## Quick Start

### 1. Start the Backend

```bash
cd backend

# Run with the included Qwen3-14B model
GENE_LLM_MODEL=models/Qwen3-14B-Q4_K_M.gguf ../../bin/gene run src/main.gene

# Or run in mock mode (no model needed)
../../bin/gene run src/main.gene
```

The backend will start on http://localhost:3000

### 2. Start the Frontend

```bash
cd frontend
npm install
npm run dev
```

The frontend will start on http://localhost:5173

### 3. Open the App

Visit http://localhost:5173 in your browser and start chatting!

## API Endpoints

### GET /api/health

Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "model_loaded": true
}
```

### POST /api/chat

Send a chat message.

**Request:**
```json
{
  "message": "Hello, how are you?"
}
```

**Response:**
```json
{
  "response": "I'm doing well, thank you!",
  "tokens_used": 10
}
```

## Configuration

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `GENE_LLM_MODEL` | Path to GGUF model file | (mock mode) |

## Mock Mode

When no model is configured, the backend runs in mock mode and returns placeholder responses. This is useful for testing the UI without requiring a large model file.

## Included Model

This example includes **Qwen3-14B-Q4_K_M** (8.4GB), a powerful 14B parameter model with excellent reasoning capabilities.

**Requirements for Qwen3-14B:**
- ~10GB RAM minimum
- GPU recommended for faster inference

## Alternative Models

For systems with less RAM, consider smaller models:

- TinyLlama 1.1B Chat (~1GB)
- Phi-2 (~2GB)
- Qwen3-4B (~3GB)

Download models from https://huggingface.co (search for GGUF format).
