## Context

`gene/serdes` already has a Gene-native text format, but large state snapshots
need finer storage boundaries than one monolithic file. The change should
provide a standard filesystem mapping without forcing every structural value to
explode into directories, and it needs to do so without paying avoidable
serialization overhead at each node.

The model in this change is:

- every logical node can be stored either inline as `<path>.gene` or exploded
  as `<path>/`
- inline storage is the default
- callers opt into directory boundaries with `^separate [...]`
- once a descendant is separated, each ancestor on the way to it must also be a
  directory

## Goals

- Add core filesystem tree serialization APIs to `gene/serdes`.
- Default to one-file storage for the root and for descendants.
- Let callers mark specific logical paths for separate child storage.
- Preserve array order without positional filename semantics.
- Round-trip loaded data back into ordinary Gene values.
- Keep exploded directory autodetection simple: Gene marker, array marker, else
  map.
- Minimize per-node encode/decode overhead in the runtime implementation.

## Non-Goals

- Checkpoint orchestration, manifest files, or compaction policies.
- General escaping for reserved root markers in generic exploded map
  directories.
- Serialization of live runtime handles such as futures, sockets, or threads.

## API

The runtime exposes:

- `gene/serdes/write_tree <path> <value>`
- `gene/serdes/write_tree <path> <value> ^separate [/* /a/* ...]`
- `gene/serdes/read_tree <path>`

`write_tree` is implemented as a native macro rather than a plain native
function so selector syntax like `/*` and `/a/*` can be read as raw path data
instead of being evaluated as ordinary access expressions.

`write_tree` treats `<path>` as a logical root path:

- with no matching `^separate` selectors, the root is written to `<path>.gene`
- if the root is separated, it is written to `<path>/`
- if `<path>` explicitly ends with `.gene`, that forces inline root storage and
  cannot be combined with selectors that require a directory root

`read_tree <path>` resolves either `<path>.gene` or `<path>/`. If both exist,
the read is rejected as ambiguous.

## Decisions

### 1. `^separate` Uses Absolute Child Selectors

`^separate` accepts an array of absolute selectors ending with `/*`:

- `[]` means no separated subtrees
- `/*` means the root stores its direct children individually
- `/a/*` means `a` stores its direct children individually

Each selector identifies a node whose direct children are separated. All
ancestor nodes of that target are also written as directories automatically.

### 2. Maps Default To Inline Children Unless A Selector Forces A Directory

When a map node is exploded, its entries become named descendants:

```text
state/
  alpha.gene
  nested.gene
```

If a deeper selector requires `nested` to be exploded, that child becomes a
directory instead:

```text
state/
  alpha.gene
  nested/
    beta.gene
```

This keeps structural values inline by default and only explodes the subtrees
the caller asked for.

### 3. Arrays Use `_genearray.gene` And Opaque Child Entry Names

Exploded arrays are represented as:

```text
arr/
  _genearray.gene
  c1f4.gene
  a92b.gene
```

`_genearray.gene` stores child entry names in order. The entry names are opaque
storage identities, not positional semantics. Selector matching still uses
logical indices like `/a/0/*`; the on-disk child entry names are an
implementation detail.

### 4. Exploded Gene Values Use `_genetype`, `_geneprops/`, And `_genechildren/`

When a Gene node itself is separated, it uses a canonical directory layout:

```text
node/
  _genetype.gene
  _geneprops/
    title.gene
  _genechildren/
    _genearray.gene
    c1f4.gene
```

Logical selector paths within a separated Gene node use synthetic path segments:

- `/_genetype`
- `/_geneprops/<name>`
- `/_genechildren/<index>`

This keeps prop names distinct from ordered children and avoids mixing root
markers with user data at the Gene node root.

`_genetype` is stored inline as `_genetype.gene` by default. If callers need to
separate the type value itself, they can target that synthetic node with a
selector such as `/a/_genetype/*`. In that case `_genetype/` is written as an
exploded structural value instead of `_genetype.gene`.

### 5. Root Directory Decoding Uses Deterministic Markers

When decoding an exploded directory:

- `_genetype.gene` means the directory is a Gene value
- otherwise `_genearray.gene` means it is an array
- otherwise it is decoded as a map

For public `read_tree`, this detection happens after resolving the logical root
path to either `<path>.gene` or `<path>/`.

An empty exploded directory therefore decodes as an empty map.

### 6. `_genetype` Remains A Known v1 Limitation

Generic exploded map directories cannot safely use root entries that collide
with the Gene autodetection marker:

- `_genetype`

This limitation is documented rather than escaped in v1. It does not apply to
inline `.gene` files.

### 7. Performance Work Stays In The Native Runtime Path

`write_tree` and `read_tree` remain native runtime entry points. The
implementation should optimize the hot path without moving tree traversal into
ordinary Gene code.

The intended optimization strategy is:

- keep directory selection and filesystem traversal in Nim
- avoid redundant serialization of the same node when deriving child entry
  names and file contents
- use specialized tree-serdes helpers for inline payload files rather than
  routing every file through avoidable wrapper allocations
- add a dedicated VM instruction or lower-level runtime primitive only if
  profiling shows the existing native entry points are the bottleneck

## Risks / Trade-offs

- Selector semantics are more flexible than path-shape-driven explosion, but
  they require a clearly documented logical path model.
- Gene nodes still need a canonical directory shape once separated, so their
  internal `_geneprops/` and `_genechildren/` structure is less minimal than
  maps.
- Opaque child entry names make arrays update-friendly, but they are not
  meaningful names and should not be treated as user-visible identifiers.
- The performance path must stay compatible with the same logical on-disk model
  so the format does not split into "fast" and "slow" variants.
