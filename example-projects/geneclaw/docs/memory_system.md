# GeneClaw Memory System Design

## Overview

A two-tier memory system for GeneClaw: **session memory** (per-conversation working context) and **long-term memory** (durable knowledge with semantic search). Markdown is the source of truth; embeddings are a derived index.

This design assumes one running GeneClaw instance serves one workspace and one agent. Long-term memory is therefore global within that instance, not partitioned by workspace or user.

## Operating Model

- `GENECLAW_HOME/memory/*` is owned by the running GeneClaw process.
- Users change long-term memory by telling the agent what to remember, correct, or forget.
- Direct edits to `MEMORY.md` by users or third-party programs are unsupported in normal operation.
- `MEMORY.md` is canonical; `.index.gene` is disposable derived state.
- V1 assumes one owning GeneClaw process. In-process memory operations are serialized; stronger cross-process coordination is out of scope.

## Architecture

```
┌─────────────────────────────────────┐
│           System Prompt             │  ← Injected every turn
│  (persona, rules, tool instructions)│
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│         Long-Term Memory            │  ← Global durable memory for this instance
│  GENECLAW_HOME/memory/MEMORY.md     │
│  GENECLAW_HOME/memory/.index.gene   │  ← Derived embedding index
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│         Session Memory              │  ← Per-conversation (exists today)
│  GENECLAW_HOME/sessions/<id>/       │
│  {role, content, meta, created_at}  │
└─────────────────────────────────────┘
```

## Layer 1: Session Memory (existing)

Already implemented in `workspace_state.gene`. No changes needed.

- Scoped to a single conversation (Slack thread, API session, etc.)
- Stores message history as `{role, content, meta, created_at_ms}` entries
- Loaded on session start, saved on each interaction
- Ephemeral — not searchable across sessions

## Layer 2: Long-Term Memory

### Storage

```
GENECLAW_HOME/memory/
├── MEMORY.md          # Source of truth — human-readable, agent-owned
└── .index.gene        # Derived embedding index (auto-generated, rebuildable)
```

**MEMORY.md** is a plain markdown file organized by headings:

```markdown
## User Preferences
- Prefers concise responses
- Bilingual: English and Chinese

## Projects
### Gene Language
- Architecture improvement branch active
- Key insight: gene-old has better type system than gene-new

## Decisions
### 2026-03-18 — Memory system design
- Two tiers: session + long-term
- Markdown source of truth with embedding search
- No daily log layer
```

Rules:
- Agent reads and writes through `memory_read`, `memory_write`, and `memory_search`
- Users request memory changes through the agent; direct file edits and external writers are unsupported
- Organized by `##` sections for chunking
- `.index.gene` is derived state; if missing or stale, the agent rebuilds it automatically

### Chunking

Split MEMORY.md into chunks at `##` heading boundaries:

```gene
# Pseudocode
(fn chunk_markdown [text]
  # Split on lines starting with "## "
  # Each chunk = heading + all content until next ## or EOF
  # Return [{^id 0 ^heading "User Preferences" ^text "..." ^hash "<sha256>"}]
)
```

Design choices:
- Chunk boundary: `##` (h2) headings — balances granularity vs context
- Nested `###` stays within parent `##` chunk
- Content before first `##` is chunk 0 (preamble)
- Each chunk gets a SHA-256 hash of its text for change detection
- Typical chunk: 100-500 tokens (good size for embedding)

### Embedding Index

`.index.gene` stores the derived index:

```gene
{
  ^file_hash "<sha256 of full MEMORY.md>"
  ^model "text-embedding-3-small"
  ^dimensions 1536
  ^chunks [
    {
      ^id 0
      ^heading "User Preferences"
      ^text "## User Preferences\n- Prefers concise responses\n..."
      ^hash "<sha256 of chunk text>"
      ^vector [0.0123 -0.0456 ...]  # 1536-dim float array
      ^offset 0                      # byte offset in MEMORY.md
      ^length 142                    # byte length
    }
    ...
  ]
}
```

### Sync Pipeline

```
memory_write request
  → acquire process-local memory lock
  → load current MEMORY.md
  → apply append/replace/create transform in memory
  → re-chunk next markdown
  → for each chunk:
      → if chunk hash unchanged: keep existing embedding
      → if chunk is new/modified: call OpenAI embedding API
  → write MEMORY.md.tmp
  → write .index.gene.tmp with matching file_hash
  → rename MEMORY.md.tmp → MEMORY.md
  → rename .index.gene.tmp → .index.gene
  → release memory lock
```

This minimizes API calls — only modified chunks get re-embedded.

### Consistency Rules

- `memory_write` holds a process-local lock so overlapping writes/rebuilds in the same GeneClaw process do not race.
- `memory_search` never trusts `.index.gene` blindly; it compares `.index.gene/file_hash` against the current `MEMORY.md` hash before using embeddings.
- If `.index.gene` is missing or stale, `memory_search` rebuilds it under the same lock before answering.
- If a write or rebuild is already in progress, memory tools may return a temporary `"memory busy"` error and the agent can retry.
- Cross-process access is unsupported in v1. Exactly one GeneClaw process should own `GENECLAW_HOME/memory`.

This is enough for v1: the store is single-owner, writes are serialized inside that owner, and stale derived state self-heals on the next search.

### Search

```
Query "what did we decide about memory?"
  → load current MEMORY.md hash
  → if .index.gene is missing or file_hash mismatches: rebuild it
  → embed query via OpenAI API (single API call)
  → cosine similarity against all chunk vectors
  → return top-k chunks (default k=5) sorted by score
  → include heading + text + score for each result
```

Cosine similarity in Gene:

```gene
(fn cosine_similarity [a b]
  (var dot 0.0)
  (var norm_a 0.0)
  (var norm_b 0.0)
  (for i in (range 0 a/.size)
    (dot = (dot + (a/i * b/i)))
    (norm_a = (norm_a + (a/i * a/i)))
    (norm_b = (norm_b + (b/i * b/i)))
  )
  (dot / ((math/sqrt norm_a) * (math/sqrt norm_b)))
)
```

## Retrieval Model

Long-term memory is tool-driven, not eagerly injected into every turn.

- The system prompt teaches the agent when to use memory tools.
- `memory_search` is used when durable prior context may matter.
- `memory_read` is used for exact section retrieval once the relevant area is known.
- `memory_write` is used after the turn when something is worth preserving.
- No special startup injection in `agent.gene` is required for v1.

## Agent Tools

### memory_search

```gene
# Search long-term memory by semantic similarity
# Input:  {^query "what are user's preferences?" ^limit 5}
# Output: [{^heading "..." ^text "..." ^score 0.89} ...]

# Flow:
# 1. Load MEMORY.md and compute current file hash
# 2. Ensure .index.gene exists and file_hash matches, rebuilding if needed
# 3. Embed query string
# 4. Cosine similarity against all chunks
# 5. Return top-k matches above threshold (0.3)
```

### memory_read

```gene
# Read canonical MEMORY.md or a specific section
# Input:  {^section "Projects"}       — returns that ## section
# Input:  {}                          — returns full file
# Output: string (markdown text)
#
# Notes:
# - Reads MEMORY.md directly
# - Does not depend on .index.gene
```

### memory_write

```gene
# Write to MEMORY.md — append or replace a section
# Input:  {^section "Decisions" ^content "### 2026-03-18 — New decision\n..." ^mode "append"}
# Modes:
#   "append"  — add content to end of section (create section if missing)
#   "replace" — replace entire section content
#   "create"  — create new section (error if exists)
# Output: {^ok true ^file_hash "<sha256>" ^reindexed true}
#
# Side effects:
# - serializes through the process-local memory lock
# - writes MEMORY.md atomically via temp file + rename
# - refreshes .index.gene to match the committed markdown
#
# Temporary failure:
# - if another memory operation is in flight, may return {^ok false ^error "memory busy"}
```

## System Prompt Additions

Add to GeneClaw's system prompt:

```
## Memory

You have a long-term memory stored in MEMORY.md. Use it wisely:

- **Before answering** questions about past context, decisions, or preferences:
  call memory_search to check what you know.
- **After important interactions** (decisions made, new facts learned,
  user preferences expressed): call memory_write to store them.
- **Be selective** — store what's worth recalling later. Skip ephemeral details.
- **Organize by topic** — use clear ## headings when creating new sections.
- **Do not ask the user to edit MEMORY.md directly** — if memory should change,
  update it yourself with memory_write.
```

## Embedding Provider

- **Model:** `text-embedding-3-small` (OpenAI)
  - 1536 dimensions, ~62k token context
  - $0.02 per 1M tokens (~$0.02 per MB of text)
  - Good balance of quality vs cost
- **Auth:** Reuse existing `OPENAI_API_KEY` from GeneClaw config
- **Endpoint:** `POST https://api.openai.com/v1/embeddings`
- **Fallback:** If no API key, `memory_read` and `memory_write` still work on plain markdown, but `memory_search` returns unavailable until embeddings can be rebuilt

## Future Enhancements (not in v1)

- **Multiple memory files** — split by topic when MEMORY.md gets large
- **Hybrid search** — blend embedding similarity with keyword/BM25 for exact names
- **Auto-compaction** — summarize old sections to keep file manageable
- **Session-to-memory promotion** — auto-extract key facts from session on close
- **Cross-process ownership** — file locks or revisioned journal if multi-process GeneClaw is needed later
- **Memory expiry** — age out stale entries

## Implementation Order

1. **Home bootstrap** — add `GENECLAW_HOME/memory` path helpers and ensure the root exists
2. **memory_read / memory_write transforms** — file operations on MEMORY.md
3. **Memory lock + atomic commit** — serialize writes/rebuilds and use temp files + rename
4. **Chunker** — split markdown by `##` headings and compute hashes
5. **Embedder** — OpenAI API call wrapper, cache by chunk hash
6. **Index store** — read/write `.index.gene`
7. **Search-time validation** — hash-check `.index.gene` and rebuild if missing/stale
8. **memory_search tool** — wire retrieval together
9. **System prompt update** — instruct the agent to use memory tools instead of asking for manual edits

## File Changes

```
src/
├── memory.gene          # NEW — long-term memory store, locking, hash checks, indexing
├── tools/memory.gene    # NEW — memory_read / memory_write / memory_search tool definitions
├── tools.gene           # MODIFY — register memory tools
└── home_store.gene      # MODIFY — bootstrap memory root/path helpers and default prompt guidance

GENECLAW_HOME/
└── memory/
    ├── MEMORY.md        # NEW — long-term memory (source of truth)
    └── .index.gene      # NEW — embedding index (auto-generated)
```
