## Context

`gene/serdes` already has a Gene-native text format, but large state snapshots
need finer storage boundaries than one monolithic file. The change should
provide a standard filesystem mapping without forcing every structural value to
explode into directories.

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
- Preserve array order without positional filenames.
- Round-trip loaded data back into ordinary Gene values.

## Non-Goals

- Checkpoint orchestration, manifest files, or compaction policies.
- Escaping reserved root markers in generic exploded map directories.
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

### 3. Arrays Use Stable Child Ids And `__order__.gene`

Exploded arrays are represented as:

```text
arr/
  __order__.gene
  c1f4.gene
  a92b.gene
```

`__order__.gene` stores child ids in order. The child ids are storage
identities, not positional filenames. Selector matching still uses logical
indices like `/a/0/*`; the stable ids are only used on disk.

### 4. Exploded Gene Values Use `genetype.gene`, `props/`, And `children/`

When a Gene node itself is separated, it uses a canonical directory layout:

```text
node/
  genetype.gene
  props/
    title.gene
  children/
    __order__.gene
    c1f4.gene
```

Logical selector paths within a separated Gene node use synthetic path segments:

- `/props/<name>`
- `/children/<index>`

This keeps prop names distinct from ordered children and avoids mixing root
markers with user data at the Gene node root.

### 5. Root Directory Decoding Uses Deterministic Markers

When decoding an exploded directory:

- `genetype.gene` means the directory is a Gene value
- otherwise `__order__.gene` means it is an array
- otherwise it is decoded as a map

For public `read_tree`, this detection happens after resolving the logical root
path to either `<path>.gene` or `<path>/`.

### 6. Reserved Marker Names Remain A Known v1 Limitation

Generic exploded map directories cannot safely use root entries that collide
with the autodetection markers:

- `genetype`
- `__order__`

This limitation is documented rather than escaped in v1. It does not apply to
inline `.gene` files.

## Risks / Trade-offs

- Selector semantics are more flexible than path-shape-driven explosion, but
  they require a clearly documented logical path model.
- Gene nodes still need a canonical directory shape once separated, so their
  internal `props/` and `children/` structure is less minimal than maps.
- Stable child ids make arrays update-friendly, but they are not meaningful
  names and should not be treated as user-visible identifiers.
