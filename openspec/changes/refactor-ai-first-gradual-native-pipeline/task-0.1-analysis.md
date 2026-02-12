# Task 0.1: Symbol-Index Regression Reproduction and Root Cause

## Reproduction

A cached GIR repro was created with a map containing many unique symbol keys:

```gene
(var m {
  ^sym_0 0
  ...
  ^sym_520 520
})
(println m)
```

Execution steps:
1. First run compiles and writes GIR cache.
2. Second run loads cached GIR in a fresh process.

Observed failure on second run:

```
Error: unhandled exception: index 396 not in 0 .. 395 [IndexDefect]
```

Stack passes through `get_symbol` while compiling/executing values loaded from GIR.

## Root Cause

`src/gene/gir.nim` serializes `Key` values as raw packed symbol indices (`int64`) in multiple places:
- scope tracker mappings
- map keys
- gene property keys

On load, those raw indices are cast back to `Key` without re-interning symbol strings for the new process. Because symbol table ordering/size is process-local, cached indices can be out of range (or wrong symbol identity), causing `get_symbol` index defects.

## Conclusion

The blocker is valid and reproducible. Fix approach for task 0.2:
- serialize keys by symbol string, not raw index
- reconstruct keys with `to_key()` on load
- keep GIR versioned to invalidate incompatible old cache files
