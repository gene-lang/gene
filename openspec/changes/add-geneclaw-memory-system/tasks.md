## 1. Implementation

- [x] 1.1 Add `GENECLAW_HOME/memory` bootstrap paths and exports.
- [x] 1.2 Implement the long-term memory store module for markdown read/write,
      chunking, hashing, and derived index rebuild.
- [x] 1.3 Add `memory_read`, `memory_write`, and `memory_search` tool
      registrations.
- [x] 1.4 Update prompt/default runtime guidance for agent-owned memory usage.
- [x] 1.5 Add tests for long-term memory read/write/search behavior and config
      exposure.

## 2. Validation

- [x] 2.1 Run targeted GeneClaw tests covering home storage and memory tools.
- [x] 2.2 Run `openspec validate add-geneclaw-memory-system --strict`.
