# String and Regex Design

This document describes the target direction for Gene string and regex support.

The working goal is:

- UTF-8 character semantics at the string core
- explicit `CString` support at the FFI boundary
- Ruby-like power for real text-processing workflows
- no requirement to reproduce every Ruby `String`, `Regexp`, or `MatchData`
  method

It builds on the current VM implementation in
[`src/gene/types/core/value_ops.nim`](../src/gene/types/core/value_ops.nim),
[`src/gene/stdlib/strings.nim`](../src/gene/stdlib/strings.nim),
[`src/gene/stdlib/regex.nim`](../src/gene/stdlib/regex.nim), and
[`src/gene/extension/c_api.nim`](../src/gene/extension/c_api.nim).

## Goals

- Make user-facing string indexing, sizing, slicing, and regex offsets operate
  on UTF-8 characters, not raw bytes.
- Keep `String` as Gene's main text type.
- Add a dedicated `CString` interop path for FFI and native extensions.
- Reach Ruby-like capability for common text tasks:
  - matching
  - captures and match data
  - search and split
  - substitution
  - trimming, casing, prefix/suffix checks
  - character/byte iteration
- Keep byte-oriented and C-oriented operations explicit instead of silently
  overloading `String`.

## Non-Goals

- Perfect method-for-method parity with Ruby.
- Full Onigmo compatibility or every Ruby regexp feature.
- Turning `CString` into a general-purpose application string type.
- Supporting arbitrary legacy encodings in phase 1.
- Solving grapheme-cluster-aware editing in the first iteration.

## Current State

Gene already has a split string model:

- At the `Value` core, strings are partly rune-aware today:
  - `value[i]` iterates UTF-8 runes for strings and symbols
  - `value.size` counts runes for strings and symbols
  - this behavior is already exercised in
    [`tests/test_types.nim`](../tests/test_types.nim)
- At the stdlib `String` method layer, behavior is inconsistent:
  - `String.length` uses byte length
  - `substr` and `char_at` are byte-indexed
  - `to_upper` / `to_lower` are ASCII-only
- Regex support is useful but still phase-1:
  - literals
  - `Regexp`
  - `RegexpMatch`
  - basic `match`, `find`, `replace`
- The C extension boundary is string-only today:
  - `gene_to_value_string(const char*)` copies a NUL-terminated input string
  - `gene_to_string(Value)` exposes a borrowed `const char*`
  - there is no explicit `CString` type or length-aware string ABI

The design goal is to unify these pieces around a clear model instead of
continuing with partial byte-based and rune-based behavior side by side.

## Core Design

### 1. `String` Is UTF-8 Text

`String` remains the primary managed text type in Gene.

Storage:

- Strings continue to store UTF-8 bytes internally.

Semantics:

- User-facing character operations use Unicode scalar values (`Rune` / `Char`).
- Character counts are not byte counts.
- Character indexing and slicing operate on character positions.

This means the current rune-aware `Value[]` and `Value.size` behavior becomes
the baseline that higher-level `String` methods must match.

### 2. `Char` Is the Core Character Unit

For phase 1, the core unit is the Unicode scalar value, not the grapheme
cluster.

That gives a practical rule set:

- `String[index]` returns `Char`
- `String.char_at` returns `Char`
- `String.length` / `String.size` count Unicode scalar values
- regex match offsets are reported in character positions

Grapheme-cluster-aware APIs can be added later if needed, but they should be
explicit and not block the UTF-8 core cleanup.

### 3. Byte Operations Must Be Explicit

Gene still needs low-level byte access, especially for FFI and protocol work.

The design direction is:

- character-oriented operations are the default for `String`
- byte-oriented operations are explicit

Expected byte-oriented surface:

- `bytesize`
- byte iteration helpers
- byte slicing helpers
- explicit conversion between `String` and `Bytes` when required

This avoids the current ambiguity where some APIs are character-based and others
quietly operate on raw bytes.

## FFI Design: `CString`

### 1. `CString` Is an Interop Boundary Type

`CString` should exist for FFI and native extension work, not as a replacement
for Gene `String`.

Intended role:

- represent a NUL-terminated C string boundary
- support marshalling to and from native calls
- make ownership and lifetime rules explicit

This keeps the managed UTF-8 `String` model clean while still supporting C APIs
ergonomically.

### 2. `String` and `CString` Must Not Be Treated as the Same Thing

They overlap, but they are not interchangeable:

- `String` is managed Gene text
- `CString` is an FFI view or marshalled buffer for external code

Important consequences:

- embedded NUL bytes are a problem for `CString` and must not be silently
  ignored
- arbitrary byte payloads should use `Bytes`, not `CString`
- returning a borrowed pointer must be clearly distinguished from returning an
  owned buffer

### 3. Recommended ABI Shape

The current C ABI should evolve from "string-only" to "string plus cstring and
length-aware helpers".

Useful additions include:

- explicit `CString` marshalling in native call descriptors / FFI signatures
- `gene_to_value_string_n(ptr, len)` for non-NUL-delimited UTF-8 input
- `gene_string_len(value)` to pair with exported string pointers
- `gene_to_cstring(value)` or an explicitly named equivalent for borrowed
  NUL-terminated access

This keeps `gene_to_string()` from carrying too many incompatible expectations.

### 4. Lifetime Rules Must Be Explicit

Two lifetime modes are needed:

- borrowed `CString`
  - valid for the duration documented by the call boundary
  - not owned by the caller
- owned `CString`
  - allocated or copied for native code that retains it
  - explicit release policy

Without this, extension and FFI code will eventually depend on unsafe pointer
lifetimes.

### 5. UTF-8 Validation Policy

For the managed `String` world, the default assumption should be valid UTF-8.

Recommended policy:

- `CString -> String` validates UTF-8 and copies into managed storage
- invalid text should fail fast or require an explicit lossy/bytes path
- raw native byte sequences belong in `Bytes`

That gives one clear text model instead of mixing text and arbitrary buffers in
the same runtime type.

## Ruby-Inspired Capability Target

The target is Ruby-like capability, not Ruby exhaustiveness.

The important thing to preserve is workflow parity:

- matching text against regexes
- extracting captures and offsets
- splitting and scanning
- substituting with backrefs and callbacks
- trimming and casing
- prefix/suffix and membership checks
- iterating over characters and bytes

That implies Gene should prioritize families of behavior, not a giant checklist
of method names.

## Regex Design Direction

### 1. Match Model

Gene should move toward the Ruby split between:

- a match-returning API
- a boolean predicate API

Practical direction:

- `match` returns `RegexpMatch | nil`
- a separate boolean predicate handles "does this match?"

The current `Regexp.process` can either become an alias or be retained as a
Gene-specific compatibility method.

### 2. `RegexpMatch` Should Cover Common Ruby Workflows

It does not need every Ruby `MatchData` method, but it should cover the core
cases:

- whole match
- captures
- start/end offsets
- named captures
- pre-match / post-match text
- indexed access helpers

The goal is to support real matching code without forcing users to reconstruct
match state manually.

### 3. Regex Features to Prioritize

The highest-value additions are:

- named captures
- named backrefs
- regex-aware `split`
- `scan`
- `sub` / `gsub` style substitution
- a documented set of supported flags beyond the current `i` and `m` baseline

The design should also document engine differences clearly, since the current
implementation is not Ruby's Onigmo engine.

### 4. Keep Common Gene Aliases Where They Help

Gene does not need to become a syntax clone of Ruby.

Reasonable compromise:

- support Ruby-style capabilities and semantics
- keep or alias a few Gene-friendly names where they improve readability
- avoid proliferating duplicate methods unless they materially improve porting

For example, `replace` / `replace_all` can coexist with `sub` / `gsub` if that
reduces migration friction.

## String API Direction

The priority surface is:

- size and indexing
- character and byte iteration
- slicing
- search
- split
- substitution
- trimming
- prefix/suffix checks
- case conversion

Representative capabilities to support:

- `substr`
- `index` / `rindex` with regex and offsets
- `split` with regex separators
- `scan`
- `sub` / `gsub`
- `strip` / `lstrip` / `rstrip`
- `start_with?` / `end_with?` equivalents
- Unicode-aware case operations
- byte-explicit counterparts where needed

This is enough to feel "full-featured like Ruby" without requiring every niche
Ruby convenience method before the design is considered successful.

## Phased Plan

### Phase 1: Unify UTF-8 Core Semantics

- keep `String` storage as UTF-8
- make stdlib `String` methods align with rune-aware core indexing and sizing
- change `length`, `size`, `substr`, `char_at`, and regex offsets to use
  character semantics
- add explicit byte APIs instead of leaving byte behavior implicit
- add regression tests for multibyte strings

### Phase 2: Add `CString` FFI Support

- introduce explicit `CString` marshalling rules
- add length-aware C API helpers
- define borrowed vs owned string-pointer lifetimes
- reject or explicitly route embedded-NUL/binary data through `Bytes`

### Phase 3: Upgrade Regex and Match Data

- move to `match -> RegexpMatch | nil`
- add a boolean predicate equivalent for fast checks
- expand `RegexpMatch`
- add named captures/backrefs
- add regex-aware `split`, `scan`, `sub`, and `gsub`

### Phase 4: Fill Out the Ruby-Inspired Everyday API

- trimming families
- prefix/suffix helpers
- richer casing and normalization support
- convenient aliases where they genuinely help Gene users
- compatibility-heavy tests based on real usage, not only unit fragments

## Boundaries and Trade-offs

- Character semantics in phase 1 should mean Unicode scalar values, not
  grapheme clusters.
- `CString` support is necessary, but it should not weaken the managed `String`
  model.
- Ruby is the capability reference, not a method-count mandate.
- Engine differences must be documented instead of hidden.

## Bottom Line

The design target is:

- UTF-8 characters at the core
- explicit `CString` support at the FFI edge
- Ruby-level usefulness for string and regex work
- a compact, intentional API instead of exhaustive Ruby cloning

That gives Gene a coherent direction:

1. fix the text model first
2. make FFI string boundaries explicit
3. make regex and match data powerful enough for real use
4. fill out the high-value string API surface without chasing every Ruby method
