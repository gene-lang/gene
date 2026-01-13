# Gene LLM Chat App

A simple chat application demonstrating Gene's HTTP server capabilities with LLM integration.

## The Gene Language

Gene is a Lisp-like programming language with a unique data structure at its core.

### The Gene Data Type (Central Concept)

The **Gene data structure** is what makes this language unique. Every Gene expression combines three components:

```
( type  ^prop1 val1 ^prop2 val2  child1 child2 ... )
  └type┘└─────properties────────┘└──children─────┘
```

For example: `(Person ^name "Alice" ^age 30 child1 child2)`
- **Type**: `Person` - the head/operator
- **Properties**: `{^name "Alice" ^age 30}` - named attributes
- **Children**: `[child1 child2]` - positional elements

This unified structure means **code IS data** (homoiconicity), enabling powerful metaprogramming.

### Key Syntax Features

```gene
# Variables
(var x 10)                    # Declaration
(x = 20)                      # Assignment

# Functions
(fn add [a b] (a + b))        # Definition
(add 1 2)                     # Call

# Maps with ^ prefix for keys
(var m {^name "Alice" ^age 30})
m/name                        # Access: "Alice"

# Arrays
(var arr [1 2 3])
arr/0                         # Access: 1

# Control flow
(if (x > 5)
  "big"
elif (x == 5)
  "equal"
else
  "small"
)

# Classes
(class Point
  (.ctor [x y]
    (/x = x)                  # / for self properties
    (/y = y)
  )
  (.fn distance _
    (sqrt ((/x * /x) + (/y * /y)))
  )
)

# Method calls
(var p (new Point 3 4))
p/.distance                   # Shorthand for no-arg methods
(p .move 1 2)                 # Method with arguments
```

### Why Gene?

- **Homoiconic**: Code is represented as Gene data structures, enabling macros and metaprogramming
- **Expressive**: Combines Lisp elegance with modern syntax conveniences
- **Integrated**: Built-in HTTP server, LLM support, and async capabilities

See `examples/full.gene` for a comprehensive syntax reference.

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
GENE_LLM_MODEL=models/Qwen3-14B-Q4_K_M.gguf ../../../bin/gene run src/main.gene

# Or run in mock mode (no model needed)
../../../bin/gene run src/main.gene
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

### POST /api/chat/new

Start a new conversation.

**Response:**
```json
{
  "conversation_id": "1"
}
```

### POST /api/chat/{id}

Send a chat message within a conversation.

**Request:**
```json
{
  "message": "Hello, how are you?"
}
```

**Response:**
```json
{
  "conversation_id": "1",
  "response": "I'm doing well, thank you!",
  "tokens_used": 10
}
```

## Persistence

The backend stores conversations in SQLite at `backend/chat.sqlite` (relative to the backend working directory).
The frontend mirrors full conversation history in browser local storage and restores the last conversation on reload.

## Manual Verification

1. `POST /api/chat/new` to get a `conversation_id`
2. `POST /api/chat/{id}` twice with different messages and confirm the second response reflects earlier context
3. Restart the backend and send another message to the same `conversation_id`, confirming history persists
4. Reload the frontend and verify the last conversation history is restored
5. Click "New Conversation" to start a fresh chat

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
