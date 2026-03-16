# Gene Stream Design

## Overview

A Gene Stream is a first-class primitive representing the ability to produce Gene values over time. A stream is **not a collection** — it does not own or store its values by default.

## Core Properties

- **Potentially infinite** — no assumed end
- **Non-materialized by default** — no implicit buffering or storage
- **Consumable incrementally** — values processed one at a time
- **Composable** — transforms chain into pipelines without realizing intermediate results

## Two Stream Types

Gene supports two stream types with a **shared operator API** but different control flow:

### Pull Stream (Sequence)
- Consumer drives: "give me the next value"
- Use cases: data processing, lazy computation, file reading, ranges
- Backpressure is implicit (consumer controls pace)
- Mental model: iterator / generator

### Push Stream (Channel)
- Producer drives: "here's a value, deal with it"
- Use cases: events, timers, network data, UI interactions
- Backpressure must be explicit (buffering, dropping, or signaling)
- Mental model: observable / async channel

### Why Two Types
Unification is hard because control flow is inverted. Wrapping one in the other always leaks:
- Pull wrapping push → needs buffering (defeats the purpose)
- Push wrapping pull → needs polling (wasteful)

The solution: **two types, one API surface**. Users learn one set of operators. The runtime handles them differently. (Precedent: Kotlin Sequence/Flow, Rust Iterator/Stream.)

## Built-in Counter

Every stream maintains a lightweight counter (single integer) tracking how many values have been emitted. This is **not** length — infinite streams never have a length.

Uses:
- Enables `take`, `drop`, `nth` without separate tracking
- Debugging/logging ("stream produced 10k values so far")
- Safety checks (warn if `collect` exceeds a threshold)

## Operations

### Lazy Transforms (build pipelines, don't execute)
| Operator | Description |
|----------|-------------|
| `stream/map` | Transform each value |
| `stream/filter` | Keep values matching predicate |
| `stream/flat-map` | Map and flatten nested streams |
| `stream/take` | First N values, then stop |
| `stream/drop` | Skip first N values |
| `stream/take-while` | Take while predicate holds |
| `stream/drop-while` | Drop while predicate holds |
| `stream/zip` | Combine two streams pairwise |
| `stream/chunk` | Group into fixed-size batches |

### Terminal Ops (trigger consumption)
| Operator | Description |
|----------|-------------|
| `stream/collect` | Materialize into a list (⚠️ dangerous on infinite) |
| `stream/reduce` | Fold values into accumulator |
| `stream/count` | Count all values (⚠️ dangerous on infinite) |
| `stream/first` | Take first value |
| `stream/last` | Take last value (⚠️ dangerous on infinite) |
| `stream/for-each` | Side-effect per value |
| `stream/any` | True if any value matches predicate |
| `stream/all` | True if all values match predicate |

### Creators
| Creator | Description |
|---------|-------------|
| `stream/from` | From explicit values: `(stream/from 1 2 3)` |
| `stream/range` | Numeric range: `(stream/range 0 100)` or infinite `(stream/range 0)` |
| `stream/generate` | From producer function: `(stream/generate f)` |
| `stream/empty` | Empty stream |
| `stream/repeat` | Repeat a value: `(stream/repeat x)` or `(stream/repeat x n)` |
| `stream/iterate` | Successive applications: `(stream/iterate f seed)` |

### Safety / Materialization
| Operator | Description |
|----------|-------------|
| `stream/collect-bounded` | Collect with max count, error/warn if exceeded |
| `stream/cache` | Memoize emitted values for replay |
| `stream/buffer` | Fixed-size buffer for push streams |
| `stream/window` | Sliding window over values |

## Error Handling

Streams **terminate on error by default**. Recovery is opt-in:

```gene
# Terminate on error (default)
(stream/map my-stream risky-fn)  ; error kills the stream

# Recover with catch
(stream/catch my-stream
  (fn [err] (stream/empty)))     ; swallow error, end stream

(stream/catch my-stream
  (fn [err] (stream/from default-val)))  ; substitute fallback
```

## Stream Fusion

Not user-facing. The runtime may fuse chained transforms (`map → filter → take`) into a single pass as an optimization. The API stays the same regardless.

## Examples

```gene
# Sum of first 100 squares
(-> (stream/range 1)
    (stream/map (fn [x] (* x x)))
    (stream/take 100)
    (stream/reduce + 0))

# Filter and collect
(-> (stream/from 1 2 3 4 5 6 7 8 9 10)
    (stream/filter (fn [x] (= 0 (% x 2))))
    (stream/collect))
; => (2 4 6 8 10)

# Infinite Fibonacci
(stream/iterate
  (fn [[a b]] [b (+ a b)])
  [0 1])

# Read lines from file (pull-based, lazy)
(-> (stream/from-file "data.txt")
    (stream/map parse-line)
    (stream/filter valid?)
    (stream/for-each process!))
```

## Open Questions

- Exact push stream backpressure semantics (drop oldest? block? signal?)
  A: drop oldest
- Parallel stream processing (`stream/par-map`?)
  A: deferred
- Transducer-style composition as alternative to chained transforms
  A: deferred
- Interaction with Gene's type system (typed streams?)
  A: deferred
