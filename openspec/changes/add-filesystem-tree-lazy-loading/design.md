## Context

`add-filesystem-tree-serdes` already defines a logical filesystem model where a
node is stored either inline as `<path>.gene` or exploded as `<path>/`, and
`^separate [...]` chooses which nodes store their direct children individually.
That format is already granular enough to support on-demand reads for many
workloads; the missing piece is a runtime surface that can keep selected nodes
backed by the tree until the user actually touches them.

The new requirement is seamlessness: a caller should be able to say
`(gene/serdes/read_tree path ^lazy [/sessions])` and keep using ordinary
container access. If `/sessions` is an exploded directory whose direct children
are stored separately, touching `/sessions/<id>` should load only that session.

The broader objective is to make filesystem-backed storage viable for large
hierarchical state. The runtime should use filesystem boundaries efficiently,
keeping unrelated subtrees cold and minimizing avoidable parse, decode, and
allocation work during common reads.

## Goals

- Add opt-in lazy tree loading to `gene/serdes/read_tree`.
- Keep the existing tree format unchanged.
- Use `^lazy` to target logical nodes, not new on-disk markers.
- Load only the metadata needed to navigate lazy directory-backed nodes.
- Materialize requested descendants on demand and memoize them per loaded tree.
- Keep lazy reads behaviorally compatible with eager reads.
- Make representative hierarchical reads substantially cheaper than eager
  whole-tree loads by avoiding unrelated filesystem reads and decodes.

## Non-Goals

- Lazy parsing inside a single serialized `.gene` payload.
- Persisting lazy intent in the stored data.
- Automatic write-through or partial flush of dirty lazy nodes.
- File watching, invalidation across processes, or live synchronization with the
  filesystem after `read_tree`.
- A separate public "lazy tree" API that callers must use after loading.

## API

The runtime exposes:

- `gene/serdes/read_tree <path>`
- `gene/serdes/read_tree <path> ^lazy [/ /sessions /sessions/archive]`

`read_tree` should accept selector literals in `^lazy [...]` without evaluating
them as ordinary access expressions. In practice this likely means `read_tree`
becomes a native macro, mirroring `write_tree`.

`^lazy` accepts absolute node selectors:

- `[]` means eager loading everywhere
- `/` means the resolved root node stays tree-backed
- `/sessions` means the `sessions` node stays tree-backed
- `/sessions/archive` means that nested node stays tree-backed

Unlike `^separate`, `^lazy` names the node itself and therefore does not use a
trailing `/*`.

## Decisions

### 1. Lazy Loading Is A Read-Side Overlay On The Existing Format

Lazy loading does not change how `write_tree` lays data out on disk. The runtime
uses the existing tree shape to decide what can be deferred:

- if a selected node is backed by a separate child file such as
  `sessions.gene`, the runtime can defer opening and parsing that file until the
  node is accessed
- if a selected node is backed by an exploded directory such as `sessions/`, the
  runtime can keep the node tree-backed and load descendants on demand
- if a selected node lives inside an already parsed inline `.gene` payload, the
  runtime cannot load it more lazily and falls back to eager behavior for that
  node

This keeps `^lazy` as a runtime optimization/control surface rather than a new
serialization format.

Callers get the best results when `^lazy` is used on nodes that are already
separate filesystem boundaries because of the underlying tree layout. Lazy
loading is therefore complementary to `write_tree ^separate [...]`: separation
creates storage boundaries, and laziness decides which of those boundaries stay
cold during reads.

### 2. Lazy Selectors Target Nodes, Not Child-Separation Boundaries

`^separate` answers "which node stores its direct children separately?", so its
selectors end in `/*`.

`^lazy` answers "which logical node should remain tree-backed until accessed?",
so its selectors target the node directly:

- `^lazy [/]` keeps the resolved root lazy
- `^lazy [/sessions]` keeps the `sessions` node lazy
- `^lazy [/sessions/archive]` keeps that descendant lazy

This distinction makes `^lazy [/sessions]` the natural spelling for
"load session entries on demand."

### 3. Runtime Representation Uses Lazy Container-Like Proxies

The implementation should represent deferred nodes with lazy runtime values such
as `LazyMap`, `LazyArray`, and `LazyGene`, or an equivalent internal mechanism.
The important contract is behavioral, not the exact type name:

- callers continue to use ordinary `/` access, methods, selectors, iteration,
  serialization, and `write_tree`
- lazy nodes present as their ordinary container families from user code
- the runtime may need targeted collection/selector dispatch changes to make
  that transparent; this is not a pure `serdes.nim` change

This gives the runtime a clean place to store tree metadata, memoized children,
and backing paths without changing the on-disk format.

### 4. Directory-Backed Lazy Nodes Load Metadata, Not Child Payloads

The runtime should eagerly load only the metadata required to navigate a lazy
directory-backed node:

- lazy maps load entry names from the directory listing, but not child payloads
- lazy arrays load `_genearray.gene` to know order and length, but not child
  payloads
- lazy Gene values detect the Gene marker and load only the metadata needed to
  enumerate `_geneprops/` and `_genechildren/`; `_genetype`, prop values, and
  child payloads stay deferred until accessed

This keeps navigation cheap while preserving the existing on-disk model.

Concrete example:

```text
state/
  config.gene
  sessions/
    alpha.gene
    beta.gene
```

With `^lazy [/sessions]`, opening `state` loads:

- directory entries for `state/`
- directory entries for `state/sessions/`

It does not read `state/config.gene`, `state/sessions/alpha.gene`, or
`state/sessions/beta.gene` until those nodes are accessed. Reading
`state/sessions/alpha` loads only `state/sessions/alpha.gene`; `beta` remains
deferred.

### 5. On-Demand Access Loads Only The Requested Descendant And Memoizes It

Lazy nodes must behave through ordinary Gene access paths. When code accesses a
map key, array index, Gene type, prop, or child under a lazy node:

- the runtime materializes only the requested descendant when the filesystem
  boundary allows it
- previously untouched siblings remain unloaded
- repeated access reuses the already materialized in-memory value for that
  `read_tree` result

Memoization is scoped to the loaded tree value, not a global cross-read cache.

### 6. Nested Lazy Selectors Survive Ancestor Materialization

Each `^lazy` selector marks its target node independently.

Example:

- `^lazy [/sessions /sessions/archive]`

If `/sessions` is accessed and therefore materialized as a map-like value, any
descendants under `/sessions` that are also matched by `^lazy` remain lazy in
that materialized subtree. Materializing an ancestor does not erase nested lazy
intent.

### 7. Behavior Remains Transparent To Callers

Lazy loading is an implementation detail of `read_tree`, not a new public value
shape. Callers should still be able to use ordinary access, selectors,
iteration, serialization, and `write_tree` on values that contain lazy nodes.

Operations that require more of the subtree may force materialization of the
needed descendants, but they must observe the same logical data as an eager
read.

The expected materialization behavior is:

- targeted key/index/type/prop/child access should load only the requested
  descendant when the filesystem boundary allows it
- lightweight metadata queries such as map key listing and size checks should
  use already loaded directory/manifest metadata where possible
- opening a lazy tree should avoid reading unrelated descendant payload files
  when directory listings and manifests are sufficient to answer navigation
  questions
- broad traversal operations such as iteration, equality, JSON/string
  serialization, and whole-tree persistence may force full materialization of
  the affected subtree

These broader loads are expected behavior, not a correctness bug.

### 8. Lazy Trees Are Read-Through, Not Write-Through

`read_tree ^lazy [...]` creates an in-memory snapshot with deferred
materialization. Mutations after a node is materialized follow ordinary
in-memory value behavior only:

- mutating the loaded value does not update backing files automatically
- persisting changes still requires an explicit `write_tree`

This keeps the first lazy-loading version focused on read scalability rather
than bidirectional synchronization.

### 9. `write_tree` Fully Materializes Lazy Values In v1

When `write_tree` receives a value that still contains lazy nodes, the runtime
should materialize any unloaded descendants needed to serialize the logical
value and then write the result normally.

This keeps `write_tree` simple and correct in the first version. More advanced
tree-preserving partial rewrite behavior can be a later optimization.

### 10. The First Version Assumes Single-Threaded Access Per Loaded Tree

Lazy materialization and memoization are scoped to a loaded tree value and are
assumed to run without concurrent mutation from multiple threads.

## Risks / Trade-offs

- Seamless lazy behavior likely requires runtime hooks in container access paths,
  not just `serdes.nim`.
- Arrays and Gene children still need manifest metadata up front, so the first
  access cost is lower but not zero.
- Eager fallback when no filesystem boundary exists preserves correctness, but
  it can hide a layout that is not benefiting from laziness.
- Transparent memoization must avoid aliasing surprises while still preventing
  duplicate filesystem reads.
