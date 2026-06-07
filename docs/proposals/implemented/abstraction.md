# Interface Abstraction Proposal

Status: implemented design-era record for Gene's Beta interface and adapter
system. The current reference is [`docs/adapter-design.md`](../../adapter-design.md).
The remaining deferred edge is more precise cycle diagnostics if Gene later
allows forward interface references.

This document is for implementers working on Gene's abstraction model. It
describes where interfaces and adapters are today, then proposes the next
semantic layer: nominal conformance checks, runtime predicates, interface
inheritance, default methods, and runtime method-signature metadata.

## Goal

Gene should keep interfaces nominal and explicit.

An interface is the public face a caller wants to see. An adapter is the
mechanism that makes an existing value present that face without mutating the
value's class. That split is stronger than Java-style interfaces because it lets
Gene retrofit mature types and foreign objects through explicit adapter views.

The abstraction model is designed to stay dependable:

- Inline and external implementations should both be checked as interface
  contracts.
- Runtime code should be able to ask whether a value can satisfy an interface
  without attempting a cast.
- Interfaces should compose through inheritance.
- Interface defaults should provide reusable behavior without creating implicit
  structural typing.
- Runtime interface metadata should preserve full method signatures, not just
  names.

## Current Model

Gene has two implementation modes:

- **Inline implementation:** a class declares that it implements one or more
  interfaces. Calling an implemented interface on an instance returns the
  original object when the class supplies the needed methods itself. If the
  interface default body is needed for dispatch, the cast returns an adapter
  view so default method `self` resolves through the interface surface.
- **External implementation:** an `implement Interface for Class` block
  registers an adapter. Calling the interface on an instance creates an adapter
  wrapper.

The runtime adapter surface supports:

- same-name fallback for declared interface fields and methods;
- computed adapter methods;
- field rename through `^from`;
- field accessor mappings with `get` and optional `set`;
- adapter-owned supplemental fields that are private to adapter bodies;
- readonly checks for interface fields on external adapters.

Before this implementation pass, the type checker was stronger for inline
implementations than external implementations. Inline class conformance was
checked by the strict checker, while external implementation blocks were mostly
validated only for local mapping errors.

The runtime and type checker now preserve interface method and field type
metadata, including method effects, validate required member completeness for
external implementations and header-level inline implementations, flatten
inherited interfaces, support default method bodies, expose public interface
reflection helpers, and detect duplicate/default conflicts.

## Implementation Status

Implemented in the current runtime:

- Inline class declarations accept `implements [A B]`.
- Interfaces accept `extends Parent` and `extends [A B]`.
- Implementing a child interface registers parent-view conformance.
- Runtime interface method metadata stores parameter descriptors, return
  `TypeId` metadata, and effects backed by the compilation unit's `TypeDesc`
  table.
- Runtime interface field metadata stores field `TypeId` metadata backed by
  `TypeDesc`.
- Runtime function/method matchers preserve declared effects so adapter
  conformance checks can reject effect-incompatible implementations.
- The `Interface` runtime class exposes `name`, `parents`, `methods`, `fields`,
  `method`, and `field` reflection helpers.
- Interface method declarations may include default bodies.
- External `implement` blocks validate required methods and fields after the
  block body has registered mappings.
- Header-level inline implementations validate after class members are defined.
- Same-name fallback counts as conformance for target methods and declared
  target class fields.
- Compatible duplicate requirements are allowed; incompatible requirements are
  rejected.
- Duplicate defaults are rejected unless the child interface, class, or adapter
  explicitly overrides the method.
- `satisfies?` is available as a global builtin and is parent-aware.
- Runtime and type-checker diagnostics include expected and actual signatures
  for interface conformance and inheritance conflicts where available.

Still future work:

- More precise diagnostics for complex inheritance cycles if Gene later allows
  forward interface references.

## Design Decisions

### 1. Keep Conformance Nominal

Interface conformance should never be inferred from shape alone. A value
satisfies an interface only when its class has an explicit inline
implementation, its class has an explicit external adapter implementation, or it
is already an adapter for that interface.

This preserves the adapter model's main advantage: a library author can decide
which view of a value is being exposed and how fields, methods, ownership, and
errors are translated.

Structural typing can be explored later, but it should not be mixed into the
core meaning of `interface` or `implement`.

### 2. Support Multiple Inline Interfaces

Inline class declarations should support a single interface or an interface
list:

```gene
(class FileBuffer implements Readable)

(class Socket implements [Readable Writable Closeable])
```

The list form is not syntactic sugar for partial conformance. The class must
fully satisfy every listed interface. If it is missing a required member from
any listed interface, the class definition is invalid.

Conflicts between listed interfaces should be handled the same way as conflicts
introduced through interface inheritance:

- identical required members are shared;
- incompatible required members are definition-time errors;
- duplicate defaults are errors unless the class overrides the method.

External adapter blocks should remain one interface at a time:

```gene
(implement Readable for DataBuffer ...)
(implement Writable for DataBuffer ...)
```

That keeps adapter descriptors simple and makes each adapter view explicit.

### 3. Make External Conformance Complete

The current adapter design tolerates partial external implementations: missing
members fail later when accessed. That weakens the meaning of an interface as a
contract and makes `satisfies?` ambiguous.

The rule is:

- `implement I for C` means `C` can fully satisfy `I`.
- Every required interface member must be satisfied by an explicit mapping,
  same-name fallback, or interface default.
- Missing required members are definition-time errors.
- Partial interface implementations are not supported.

If a library only wants to expose part of a larger surface, it should define a
smaller interface for that surface. Interfaces should remain precise contracts,
not optional bags of methods.

Same-name fallback counts as conformance. This keeps the adapter form concise
for classes that already expose the right names while still requiring an
explicit `implement` declaration to opt into the interface.

### 4. Check External Implementations With An Adapter Descriptor

External conformance cannot be checked by comparing the interface directly
against the target class shape. Adapters intentionally change the shape.

Instead, the checker should build an adapter-conformance descriptor from the
`implement` block:

| Interface member | Descriptor source |
|---|---|
| Method | explicit adapter method, same-name target method, or interface default |
| Field | explicit `^from` mapping, accessor mapping, or same-name target field |
| Readonly field | getter-only accessor, readonly view of target field, or read-only direct mapping |
| Supplemental field | adapter-owned state; does not satisfy an interface field unless explicitly exposed |

The descriptor is then checked against the interface contract. This catches
missing members, wrong method arity, incompatible types, invalid readonly
writes, and duplicate/conflicting mappings before the adapter is used.

In gradual mode, missing type information can remain `Any`. In strict mode, a
known mismatch should be an error.

The runtime should also validate completeness at the end of every external
`implement` block. That end-of-block check covers non-strict mode and dynamic
cases where the type checker cannot prove the target class shape.

### 5. Add A Nominal `satisfies?` Predicate

Runtime code needs a non-throwing conformance check:

```gene
(satisfies? obj Readable)
```

`satisfies?` is a global builtin for now, not a method added to every object.

`satisfies?` should be side-effect-free. It must not create an adapter, call an
adapter constructor, or evaluate user methods. It only answers whether the value
can be viewed as the interface.

Recommended semantics:

- `true` for an object whose class inline-implements the interface;
- `true` for an object whose class has an external implementation for the
  interface;
- `true` for an adapter whose visible interface is the requested interface or a
  child of it;
- `true` for transitive parent interfaces;
- `false` otherwise.

This gives protocol-style dispatch a cheap guard while preserving explicit
adapter creation through normal interface calls.

### 6. Add Interface Inheritance With Conflict Detection

Interfaces should be able to compose other interfaces:

```gene
(interface ReadWrite extends [Readable Writable])
```

Inheritance should be member composition, not just parent-name storage.
Definition-time validation must detect conflicts before any class implements the
child interface.

Rules:

- Parent cycles are errors.
- Duplicate inherited members with identical contracts are allowed.
- Duplicate members with incompatible kinds, types, readonly flags, arity,
  effects, or return types are errors.
- A child interface may refine a member only if the refinement is compatible
  with every inherited declaration.
- Implementing a child interface implies satisfying every transitive parent.

For runtime lookup, prefer flattening at definition or registration time. A
class implementing `ReadWrite` should also get parent-view implementation
entries for `Readable` and `Writable`, so `(Readable obj)` and
`(Writable obj)` remain O(1) lookups.

### 7. Allow Default Method Bodies

Interface methods should be allowed to provide default bodies:

```gene
(interface Named
  (field name String)

  (method display-name [] -> String
    /name))
```

Default bodies are not structural conformance. They are behavior attached to a
nominal interface and used only after a class or adapter explicitly implements
that interface.

Dispatch order should be explicit.

For inline class implementations:

1. Class method.
2. Interface default body.

For external adapter implementations:

1. Explicit adapter method.
2. Same-name wrapped method, when fallback is permitted.
3. Interface default body.

When a default method is called through an adapter, `self` is the adapter view,
not the wrapped object. This means `/field` and method calls resolve through the
interface surface.

If explicit hidden mappings are added later, hidden should stop lookup and
suppress both same-name fallback and interface defaults.

When interface inheritance is present, multiple inherited defaults for the same
method are an error unless the child interface or the implementation overrides
the method. This avoids inventing method-resolution-order rules.

### 8. Preserve Full Runtime Method Signatures

Runtime interface metadata should carry the same contract the type checker sees.

`InterfaceMethod` should store at least:

- method name;
- positional, variadic, and keyword parameter metadata;
- parameter `TypeDesc` metadata;
- return `TypeDesc` metadata;
- effects, when effect metadata is available;
- optional default callable.

`InterfaceProp` should continue to store:

- field name;
- field `TypeDesc` metadata;
- readonly flag.

This enables reflection, adapter validation, runtime diagnostics, and optional
runtime enforcement. Runtime enforcement can be strict-mode-only at first to
avoid changing loose-mode behavior too broadly.

## Implementation Record

The core phases have been implemented in this order.

### Phase 1: Metadata Groundwork

- Extend runtime interface method metadata to store full signatures.
- Populate field and method type metadata when executing interface declaration
  instructions.
- Keep runtime behavior unchanged except for improved validation and
  diagnostics.

### Phase 2: `satisfies?`

- Add a nominal runtime predicate.
- Implement parent-aware behavior so child-interface conformance implies parent
  satisfaction.
- Add tests for inline implementations, external implementations, already
  adapted values, negative cases, and no-side-effect behavior.

### Phase 3: External Conformance Checking

- Build adapter-conformance descriptors from external `implement` blocks.
- Validate explicit mappings, same-name fallbacks, accessors, readonly rules,
  and method signatures against the interface.
- At the end of each external `implement` block, reject missing required
  members. There is no partial-adapter mode.
- Preserve external blocks as one-interface declarations; multi-interface
  convenience belongs to inline `implements [A B]`.

### Phase 4: Interface Inheritance

- Add parent metadata to compile-time and runtime interface representations.
- Flatten inherited members and reject conflicts at interface definition time.
- Register parent-view implementations so child conformance implies parent
  conformance.

### Phase 5: Default Methods

- Allow interface method bodies in the compiler and type checker.
- Compile default bodies into interface method metadata.
- Implement the dispatch order for inline and external implementations.
- Reject inherited default conflicts unless explicitly overridden.

## Completed Follow-up Work

| # | Work | Impact |
|---|---|---|
| 1 | Full effect metadata | Runtime signature parity with the type checker |
| 2 | Public reflection helpers | Interface signatures are inspectable from Gene code |
| 3 | Diagnostic polish | Errors for conformance and inheritance conflicts include signature context |

## Test Plan

Core implementation coverage includes:

- Inline class satisfies a complete interface.
- Inline class satisfies multiple complete interfaces with
  `implements [A B]`.
- Inline class missing a required member is rejected.
- Inline class missing a required member from any listed interface is rejected.
- Inline class implementing multiple interfaces with conflicting required
  members is rejected.
- External adapter satisfies a complete interface through explicit methods.
- External adapter satisfies a method through same-name fallback.
- External adapter missing a required member is rejected.
- `satisfies?` returns true for inline implementations.
- `satisfies?` returns true for every interface listed in inline
  `implements [A B]`.
- `satisfies?` returns true for externally adaptable values without creating an
  adapter.
- `satisfies?` returns true for already adapted values.
- `satisfies?` returns false for unregistered values.
- Parent interface satisfaction works transitively.
- Inherited member conflicts are rejected at interface definition time.
- Interface default method is used when no class or adapter method exists.
- Explicit class or adapter method overrides an interface default.
- Multiple inherited defaults conflict unless overridden.

Remaining coverage targets:

- Parent cycles are rejected with precise diagnostics if forward interface
  references are later allowed.

## Non-Goals

- **Structural typing:** no `satisfies?` based only on field and method shape.
- **Partial implementations:** no `partial implement` and no `^partial` mode.
  Split large interfaces into smaller interfaces instead.
- **Implicit adapter synthesis:** no automatic wrapper just because two values
  happen to look compatible.
- **Multi-interface external `implement` blocks:** external adapters stay one
  interface at a time. Inline class declarations support `implements [A B]`.
- **Sealed interfaces:** useful for some package boundaries, but not required
  for the abstraction model.
- **A full trait system:** conflict detection and defaults should stay simple;
  no method-resolution-order machinery in this proposal.
