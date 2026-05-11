# AOP migration history

This page is historical context for maintainers. It records how Gene moved from
a broad aspect-oriented-programming experiment to the current **Beta** explicit
runtime interception surface.

Current users should read [`docs/interception.md`](../../interception.md). The
current API is explicit interception only: `(interceptor ...)` for selected class
methods, `(fn-interceptor ...)` for standalone callables, direct callable
application, and `/.enable` / `/.disable` controls.

## Current status

The legacy AOP public API has been removed from the current runtime surface. Old
programs that used the historical definition form, dot-application helpers, or
old interception toggle method names must migrate to explicit interception before
running on this runtime.

The current Beta contract preserves expanded positional arguments and keyword
pairs through returned wrappers for supported class methods and standalone
callables. Direct interceptor application remains positional-only: keyword
options on the application call itself are rejected with
`GENE.INTERCEPT.KEYWORD_UNSUPPORTED`.

The old design-era AOP material below is not a current feature contract. Broad
pointcuts, constructor/destructor interception, exception interception, regex
selectors, priority controls, reset/unapply, async wrapping, and
macro-transparent wrapping remain unsupported unless a future proposal adds and
verifies them.

## Migration summary

| Historical capability | Current replacement |
| --- | --- |
| Broad class-aspect-style definition | `(interceptor Name [targets] ...)` |
| Class wrapper installation through a dot helper | Direct class application such as `(Name Class "method")` |
| Standalone function wrapper creation through a dot helper | `(fn-interceptor Name [f] ...)` plus direct `(Name callable)` application |
| Old wrapper toggle methods | `wrapper/.enable` and `wrapper/.disable` |
| Old definition-wide toggle spelling, where old code used it | `Name/.enable` and `Name/.disable` |

## Evidence trail

- The original implementation exposed broad AOP-era language that proved too
  large for a durable public contract.
- The replacement direction narrowed the surface to explicit class and function
  interception, two-level enablement, targeted `GENE.INTERCEPT` diagnostics,
  public examples, and OpenSpec coverage.
- The historical public spellings were removed so new documentation and examples
  teach one current interception model.

## Current implementation notes

The implementation uses one shared interception engine for class method and
standalone callable wrappers. Interceptor definitions carry advice tables;
interception application wrappers carry the original callable, the definition
that produced the wrapper, the mapped target parameter, and an application-level
enabled flag.

Class application prevalidates all mappings before installing any wrapper. This
keeps invalid multi-method application atomic: if a later method mapping fails,
earlier methods are not partially wrapped. Installation invalidates method
dispatch assumptions by updating class method storage and runtime-type method
callables. Enable/disable controls remain cheap field flips and do not rebuild
method tables or wrapper chains.

Diagnostics for invalid explicit applications use `GENE.INTERCEPT` marker
families so fixtures can assert the failure category without freezing every
human-readable word.
