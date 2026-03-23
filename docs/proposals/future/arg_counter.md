# Argument Counting in the VM

When constructing calls (functions, methods, `gene` forms, array literals with spreads, etc.) the VM needs to know how many arguments were pushed before dispatching. Because spreads and helper routines can add an arbitrary number of values, we avoid hand-maintaining counters and instead track stack bases alongside the value stack.

## Design

We maintain a parallel stack of base indices:

- On entering a call build, push the current stack index (after pushing the callee/receiver).
- Push arguments normally (including expanding spreads).
- Before invocation, pop the base and compute `argCount = stackIndex - (base + 1)` (exclude the callee slot). Pass this to the call machinery; afterwards the callee will pop its frame and restore the stack height.

This behaves like a classic `bp`/`sp` pairing and works for nested calls. We can implement the base stack as a simple `seq[int]` or a preallocated array with manual pointer—both give amortized O(1) push/pop, while a linked list would introduce unnecessary allocation overhead.

## Next Steps

1. Add a `CallBaseStack` helper (seq-backed) and integrate with the VM’s stack manipulation routines.
2. Update call builders (functions, methods, gene forms, array literals) to push/pop base markers whenever they start/end argument collection.
3. Audit spread operators and helper macros to ensure they only use the value stack, letting the base stack track arity automatically.

