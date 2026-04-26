# AOP migration history

This page is historical context for maintainers. It records how Gene moved from
a broad Experimental aspect-oriented-programming experiment to the current
explicit runtime interception surface.

Current users should read [`docs/interception.md`](../../interception.md). The
current API is explicit interception only: `(interceptor ...)` for selected class
methods, `(fn-interceptor ...)` for standalone callables, direct callable
application, and `/.enable` / `/.disable` controls.

## Status

The legacy AOP public API has been removed from the current runtime surface. Old
programs that used the historical definition form, dot-application helpers, or
old interception toggle method names must migrate to explicit interception before
running on this runtime.

The old design-era AOP material below is not a current feature contract. Broad
pointcuts, constructor/destructor interception, exception join points, regex
selectors, priority controls, reset/unapply, keyword forwarding, async wrapping,
and macro-transparent wrapping remain unsupported unless a future proposal adds
and verifies them.

## Migration summary

| Historical capability | Current replacement |
| --- | --- |
| Broad class-aspect-style definition | `(interceptor Name [targets] ...)` |
| Class wrapper installation through a dot helper | Direct class application such as `(Name Class "method")` |
| Standalone function wrapper creation through a dot helper | `(fn-interceptor Name [f] ...)` plus direct `(Name callable)` application |
| Old wrapper toggle methods | `wrapper/.enable` and `wrapper/.disable` |
| Old definition-wide toggle spelling, where old code used it | `Name/.enable` and `Name/.disable` |

## Evidence trail

- M004 audited the original implementation and kept it Experimental while the
  replacement direction was decided.
- M005 introduced explicit class and function interception, two-level enablement,
  targeted `GENE.INTERCEPT` diagnostics, public examples, and OpenSpec coverage.
- `remove-legacy-aop-surface` removed the historical public spellings and renamed
  practical tests/runtime-facing internals toward interception terminology.

## Current implementation notes

The implementation still uses one shared interception engine for class method and
standalone callable wrappers. Interceptor definitions carry advice tables;
interception application wrappers carry the original callable, the definition
that produced the wrapper, the mapped target parameter, and an application-level
active flag.

Class application prevalidates all mappings before installing any wrapper. This
keeps invalid multi-method application atomic: if a later method mapping fails,
earlier methods are not partially wrapped. Installation invalidates method
dispatch assumptions by updating class method storage and runtime-type method
callables. Enable/disable controls remain cheap field flips and do not rebuild
method tables or wrapper chains.

Diagnostics for invalid explicit applications use stable `GENE.INTERCEPT` marker
families so fixtures can assert the failure category without freezing every
human-readable word.
