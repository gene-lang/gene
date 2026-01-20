# Gene LLM Chat App

A full-stack chat application demonstrating Gene's HTTP server capabilities with LLM integration, tool support, and AI image generation.

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
  (ctor [x y]
    (/x = x)                  # / for self properties
    (/y = y)
  )
  (method distance _
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
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    Frontend     │────▶│    Backend      │────▶│   Local LLM     │
│   (React/Vite)  │     │    (Gene)       │     │  (llama.cpp)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                │                       │
                                │                       │ (tool call)
                                ▼                       ▼
                        ┌─────────────────┐     ┌─────────────────┐
                        │    SQLite DB    │     │    ComfyUI      │
                        │  (chat history) │     │  (image gen)    │
                        └─────────────────┘     └─────────────────┘
```

```
llm_app/
├── frontend/          # React chat interface (Vite)
│   ├── src/
│   │   ├── App.jsx    # Main chat component
│   │   └── main.jsx   # Entry point
│   └── vite.config.js # Proxy configuration
└── backend/
    └── src/
        ├── main.gene      # Server entry point, routing
        ├── config.gene    # Configuration and env vars
        ├── db.gene        # SQLite database functions
        ├── llm.gene       # LLM initialization and prompts
        ├── handlers.gene  # HTTP request handlers
        ├── helpers.gene   # Utility functions
        ├── tools.gene     # Tool registry and implementations
        └── comfyui.gene   # ComfyUI integration
```

## Features

- **Chat with Local LLM**: Uses llama.cpp for local inference with streaming responses
- **Conversation History**: SQLite-backed persistent chat history
- **Tool Support**: LLM can use tools to extend its capabilities
- **Streaming Responses**: Real-time token streaming via Server-Sent Events (SSE)
- **Image Generation**: Integration with ComfyUI for AI image generation

### Available Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `get_time` | Get current date and time | - |
| `calculate` | Evaluate mathematical expressions | `expression` |
| `get_weather` | Get weather for a location (mock) | `location` |
| `web_search` | Search via Google Custom Search API | `query`, `num` |
| `read_url` | Fetch and extract text from URLs | `url`, `max_chars` |
| `create_image` | Generate images via ComfyUI/Stable Diffusion | `prompt` |
| `run_code` | Execute code in sandbox (Python/Gene/Shell) | `language`, `code` |

## Prerequisites

- Gene language runtime (build with `-d:geneLLM` flag for LLM support)
- Node.js 18+ (for frontend)
- Optional: GGUF model file for real LLM inference
- Optional: ComfyUI for image generation
- Optional: Google API credentials for web search

## Quick Start

There are two ways to run the LLM app: using Docker (recommended) or running locally.

### Option A: Docker (Recommended)

Docker provides an isolated environment with all dependencies pre-installed.

#### 1. Prepare Models Directory

```bash
# Create models directory in gene root
mkdir -p models

# Download or copy your GGUF model file
# Example: cp /path/to/your/model.gguf models/model.gguf
```

#### 2. Build and Run with Docker Compose

```bash
cd gene

# Build the Docker image (first time only, takes several minutes)
docker-compose build

# Start the container
docker-compose up

# Or run in background
docker-compose up -d
```

The backend starts on http://localhost:4080

#### 3. Test the API

```bash
# Health check
curl http://localhost:4080/api/health

# Test code execution
curl -X POST http://localhost:4080/api/oneshot \
  -H "Content-Type: application/json" \
  -d '{"message": "Run this Python code: print(2+2)"}'
```

#### Docker Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GENE_LLM_MODEL` | `/models/model.gguf` | Path to GGUF model in container |
| `COMFYUI_URL` | `http://host.docker.internal:8188` | ComfyUI URL on host |
| `CODE_EXEC_TIMEOUT` | `30` | Code execution timeout (seconds) |

#### Docker Volumes

| Host Path | Container Path | Description |
|-----------|----------------|-------------|
| `./models` | `/models` | LLM model files (read-only) |
| `./example-projects/llm_app/backend/chat.sqlite` | `/app/data/chat.sqlite` | Chat database |

### Option B: Local Development

#### 1. Build Gene with LLM Support

```bash
cd gene
nimble build -d:geneLLM
```

#### 2. Start the Backend

```bash
cd example-projects/llm_app/backend

# With LLM model
GENE_LLM_MODEL=/path/to/model.gguf ../../../bin/gene run src/main.gene

# Or in mock mode (no model needed)
../../../bin/gene run src/main.gene
```

The backend starts on http://localhost:4080

#### 3. Start the Frontend

```bash
cd example-projects/llm_app/frontend
npm install
npm run dev
```

The frontend starts on http://localhost:5173

#### 4. Open the App

Visit http://localhost:5173 in your browser and start chatting!

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GENE_LLM_MODEL` | No | - | Path to GGUF model file (mock mode if unset) |
| `COMFYUI_URL` | No | `http://127.0.0.1:8188` | ComfyUI server URL for image generation |
| `GOOGLE_API_KEY` | No | - | Google API key for web search tool |
| `GOOGLE_CSE_ID` | No | - | Google Custom Search Engine ID |
| `CODE_SANDBOX_DIR` | No | `/tmp/gene-sandbox` | Directory for code execution sandbox |
| `CODE_EXEC_TIMEOUT` | No | `30` | Timeout for code execution (seconds) |

## API Endpoints

### Chat Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/health` | Health check, returns model status |
| `POST` | `/api/chat/new` | Create new conversation |
| `POST` | `/api/chat/{id}` | Send message to conversation |
| `GET` | `/api/chat/{id}/stream?message=...` | Stream chat response via SSE |

### Image Generation Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/image/health` | Check ComfyUI connection |
| `POST` | `/api/image/generate` | Generate image with ComfyUI |
| `GET` | `/api/image/view` | Proxy image from ComfyUI |

### One-shot Endpoint

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/oneshot` | Single message with tools, no history |

### Example curl Requests

**One-shot chat (stateless, with tools):**
```bash
curl -X POST http://localhost:4080/api/oneshot \
  -H "Content-Type: application/json" \
  -d '{"message": "What time is it?"}'
```

**One-shot with image generation:**
```bash
curl -X POST http://localhost:4080/api/oneshot \
  -H "Content-Type: application/json" \
  -d '{"message": "Generate an image of a cat wearing a hat"}'
```

**Direct image generation (bypasses LLM):**
```bash
curl -X POST http://localhost:4080/api/image/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "a beautiful sunset over mountains, photorealistic"}'
```

**Image generation with options:**
```bash
curl -X POST http://localhost:4080/api/image/generate \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "a cyberpunk city at night",
    "negative_prompt": "blurry, low quality",
    "width": 1024,
    "height": 1024,
    "steps": 25,
    "cfg": 7.5
  }'
```

## Tool Usage Examples

The LLM automatically detects when to use tools:

- "What time is it?" → uses `get_time`
- "Calculate 15% of 230" → uses `calculate`
- "Search for Gene programming language" → uses `web_search`
- "Summarize https://example.com" → uses `read_url`
- "Generate an image of a sunset over mountains" → uses `create_image`
- "Write a Python script that prints the first 10 Fibonacci numbers" → uses `run_code`

### Code Execution Examples

The `run_code` tool allows the LLM to execute code in a sandboxed environment:

```bash
# Execute Python code
curl -X POST http://localhost:4080/api/oneshot \
  -H "Content-Type: application/json" \
  -d '{"message": "Run Python: import math; print(math.pi)"}'

# Execute shell commands
curl -X POST http://localhost:4080/api/oneshot \
  -H "Content-Type: application/json" \
  -d '{"message": "Run shell command: echo Hello from the sandbox"}'

# Data analysis with pandas
curl -X POST http://localhost:4080/api/oneshot \
  -H "Content-Type: application/json" \
  -d '{"message": "Write Python code to create a simple dataframe with pandas and print it"}'
```

**Security Notes:**
- Code runs in an isolated sandbox directory
- Execution has a 30-second timeout (configurable via `CODE_EXEC_TIMEOUT`)
- Python has access to numpy, pandas, and matplotlib
- Shell commands run with limited privileges

## Image Generation Setup

To enable AI image generation:

1. Install and run [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
2. Download an SDXL model (default expects `juggernautXL_v9.safetensors`)
3. Set the `COMFYUI_URL` environment variable for both backend and frontend

When the `create_image` tool is used:
1. LLM decides to call the `create_image` tool based on user request
2. Backend sends a Stable Diffusion workflow directly to ComfyUI
3. Backend polls ComfyUI until image generation completes
4. Tool returns image URL in format `/generated_images?filename=...`
5. LLM includes the URL in an HTML img tag in its response
6. Frontend proxies `/generated_images` requests to ComfyUI's `/view` endpoint

This architecture keeps ComfyUI internal (not publicly exposed) while allowing generated images to be displayed in the chat.

## Persistence

- **Backend**: Conversations stored in SQLite at `backend/chat.sqlite`
- **Frontend**: Conversation history mirrored in browser local storage

## Adding New Tools

1. Edit `backend/src/tools.gene`
2. Register the tool:
   ```gene
   (register_tool "tool_name"
     "Tool description"
     {^param1 "Parameter description"}
     (fn [args]
       (var param1 (args .get "param1" ""))
       # Implementation
       {^result "Tool result"}
     )
   )
   ```
3. Update the static system prompt in `build_system_prompt`

## Recommended Models

| Model | Size | RAM Required | Notes |
|-------|------|--------------|-------|
| TinyLlama 1.1B | ~1GB | 2GB | Fast, limited capability |
| Phi-2 | ~2GB | 4GB | Good for simple tasks |
| Qwen3-4B | ~3GB | 6GB | Balanced performance |
| Qwen3-14B | ~8GB | 12GB | Excellent reasoning |

Download models from [Hugging Face](https://huggingface.co) (search for GGUF format).

## Known Issues

- **Stack Overflow on Variable Resolution**: Accessing module-level variables from exported functions can cause stack overflow. See `docs/known_issues/var_stack_overflow.md`.
- **Single-threaded Server**: The Gene HTTP server cannot make HTTP calls to itself.
- **Binary Data Handling**: Proxying binary data through Gene requires temp files.

## License

Part of the Gene programming language project.
