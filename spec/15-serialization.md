# 15. Serialization

## 15.1 JSON (Plain)

Standard JSON conversion:

```gene
(gene/json/parse "{\"name\":\"Alice\",\"age\":30}")
# => {^name "Alice" ^age 30}

(gene/json/stringify {^name "Alice" ^age 30})
# => "{\"name\":\"Alice\",\"age\":30}"
```

### Type Mapping

| Gene Type | JSON Type   |
|-----------|-------------|
| Int       | number      |
| Float     | number      |
| String    | string      |
| Bool      | true/false  |
| Nil       | null        |
| Array     | array       |
| Map       | object      |

## 15.2 JSON (Tagged / Gene-Aware)

Round-trip serialization preserving Gene-specific types:

```gene
(gene/json/serialize value)      # Gene → tagged JSON
(gene/json/deserialize string)   # Tagged JSON → Gene
```

Tagged values use a `#GENE#` prefix:
- Symbols: `"#GENE#symbol_name"`
- Gene nodes: `{"genetype": "#GENE#type", "children": [...], ...props}`

## 15.3 GIR (Gene Intermediate Representation)

Binary format for compiled Gene bytecode:

```bash
# Compile to GIR
gene compile file.gene           # Writes to build/file.gir

# Run GIR directly (2-5× faster startup)
gene run build/file.gir

# Smart caching: auto-uses GIR if up-to-date
gene run file.gene               # Checks build/file.gir first
```

### GIR Contents
- Instruction sequences
- Constant pool
- Symbol table
- Type metadata (if type checking enabled)
- Debug info (if `--emit-debug`)
- Source hash (for cache invalidation)
- Compiler version (for compatibility)

### Cache Invalidation
GIR is invalidated when:
- Source file changes (hash mismatch)
- Compiler version changes
- `--no-gir-cache` flag is passed

## 15.4 Gene Serialization Format

Gene has two serialization concerns that should stay separate:

- **Text payload conversion** turns Gene values into Gene-native serialized text and back.
- **Filesystem persistence** writes and reads those serialized payloads from files and directories.

### Text payload API

`gene/serdes/serialize` and `gene/serdes/deserialize` operate on serialized text payloads only. They do not accept filesystem paths and do not perform file I/O.

```gene
(var text (gene/serdes/serialize {^name "Alice" ^age 30}))
(gene/serdes/deserialize text)
```

Serialized text is represented with a `gene/serialization` envelope when shown in examples:

```gene
(gene/serialization {^name "Alice" ^age 30})
```

The CLI currently ships `gene deser` / `gene deserialize` for inspecting serialized text:

```bash
gene deser -e '(gene/serialization [1 2 3])'
```

### Filesystem persistence API

Filesystem persistence uses the `gene/serdes` file API:

```gene
(gene/serdes/write "state/root.gene" {^name "Alice" ^age 30})
(gene/serdes/read "state/root.gene")
(gene/serdes/read_file "state/root.gene")
(gene/serdes/read_dir "state/sessions" ^shape "array" ^order "name")
```

`read` is the convenience form for reading one serialized file and has the same public behavior as `read_file`. Directory-backed collections use `read_dir` so the caller can choose shape and ordering explicitly.

The supported filesystem surface is exactly:

- `gene/serdes/write`
- `gene/serdes/read`
- `gene/serdes/read_file`
- `gene/serdes/read_dir`

A serialized parent file may contain explicit references to child files or directories:

```gene
(gene/serialization
  {^profile (gene/serdes/read_file "child.gene")
   ^sessions (gene/serdes/read_dir "sessions" ^shape "array" ^order "name")})
```

These forms are serializer-owned data forms. During deserialization, `read_file` and `read_dir` references are resolved by the deserializer using the containing serialized file as path context. They are not arbitrary Gene runtime evaluation, and resolving them must not invoke user functions, macros, methods, or module loading.

### Relative references and path safety

Nested file and directory references are container-relative. If a serialized file is read from `state/root.gene`, then `(gene/serdes/read_file "child.gene")` resolves to the child next to `root.gene`, and `(gene/serdes/read_dir "sessions" ^shape "array" ^order "name")` resolves to the sibling `sessions` directory.

Filesystem serializer reads fail closed. Unsafe absolute paths, traversal escapes, malformed reference options, missing targets, unreadable targets, invalid serialized payloads, and file or directory reference cycles must raise diagnostics that include the target path and containing-file context. They must not silently return `nil`, an empty collection, or a partially loaded value.

### Eager and lazy references

File and directory references load eagerly by default. A missing or invalid target therefore fails before the parent value is returned.

Use `^lazy true` when a reference should defer I/O until the value is accessed:

```gene
(gene/serialization
  {^large_profile (gene/serdes/read_file "profiles/large.gene" ^lazy true)
   ^sessions (gene/serdes/read_dir "sessions" ^shape "array" ^order "name" ^lazy true)})
```

A lazy reference behaves like the loaded value during normal access and caches the materialized value after the first successful load. Lazy failures are reported when the value is materialized, with the target path and original containing-file context preserved in the diagnostic.

### Directory shape and ordering

`read_dir` turns a directory of serialized child files into a collection. The public options are explicit so directory reads remain deterministic:

- `^shape "array"` returns an ordered array of child values.
- `^shape "map"` returns a keyed map using deterministic child identifiers derived from file names.
- `^order "name"` reads children in deterministic filename order.
- `^order "ctime"` reads by creation time when the platform can provide stable creation-time metadata. If that cannot be provided, the read must fail explicitly or use a documented deterministic fallback.

Invalid directory targets, unsupported shapes or order modes, duplicate options, and malformed option values are errors.

### Writer externalization

`gene/serdes/write` can externalize selected sub-values into deterministic child files or directories. The parent payload stores explicit `read_file` or `read_dir` references in place of the externalized values:

```gene
(gene/serdes/write
  "state/root.gene"
  {^profile {^name "Alice"} ^sessions [{^id 1} {^id 2}]}
  ^externalize [/profile /sessions])
```

The generated child names and reference paths must be stable for identical writes so serialized output diffs are meaningful. Selector-derived, key-derived, or content-derived child identifiers are treated as untrusted input: empty names, absolute names, traversal segments, path separators, and other unsafe names are rejected before any path is joined or written.

### Migration note

Earlier filesystem serialization drafts exposed `read_tree` and `write_tree`. Those names are removed and replaced by the unified `write`, `read`, `read_file`, and `read_dir` model; they are not compatibility aliases and should not appear in live examples.

---

## Potential Improvements

- **JSON-specific serialization hooks**: `gene/serdes` supports custom class `serialize` / `deserialize` hooks, but `gene/json/*` does not consult those hooks automatically.
- **Binary serialization**: GIR is for bytecode only. No general-purpose binary serialization for Gene data structures.
- **YAML/TOML/XML**: No support for other common formats.
- **Streaming JSON**: Large JSON must be fully parsed into memory. No streaming/SAX-style parser.
- **Pretty printing**: `gene/json/stringify` produces compact output. No built-in pretty-print with indentation.
- **Serialization of functions**: Functions cannot be serialized. This limits what can be saved/transmitted.
- **GIR versioning**: GIR format changes require full recompilation. No migration path between GIR versions.
- **Circular reference handling**: JSON serialization does not detect circular references, which would cause infinite loops.
