## Symbol table: to_symbol_value, to_key, get_symbol.
## Included from core.nim — shares its scope.

#################### Symbol #####################

var SYMBOLS*: ManagedSymbols
var SYMBOLS_SHARED*: ptr ManagedSymbols = nil
var SYMBOLS_LOCK: Lock

initLock(SYMBOLS_LOCK)

proc active_symbols_ptr(): ptr ManagedSymbols {.inline.} =
  if SYMBOLS_SHARED != nil:
    SYMBOLS_SHARED
  else:
    addr SYMBOLS

proc get_symbol*(i: int): string {.inline.} =
  {.cast(gcsafe).}:
    acquire(SYMBOLS_LOCK)
    try:
      result = active_symbols_ptr()[].store[i]
    finally:
      release(SYMBOLS_LOCK)

proc get_symbol_gcsafe*(i: int): string {.inline, gcsafe.} =
  {.cast(gcsafe).}:
    acquire(SYMBOLS_LOCK)
    try:
      result = active_symbols_ptr()[].store[i]
    finally:
      release(SYMBOLS_LOCK)

proc to_symbol_value*(s: string): Value =
  {.cast(gcsafe).}:
    acquire(SYMBOLS_LOCK)
    try:
      let symbols = active_symbols_ptr()
      let found = symbols[].map.get_or_default(s, -1)
      if found != -1:
        let i = found.uint64
        result = cast[Value](SYMBOL_TAG or i)
      else:
        let new_id = symbols[].store.len.uint64
        # Ensure symbol ID fits in 48 bits
        assert new_id <= PAYLOAD_MASK, "Too many symbols for NaN boxing"
        result = cast[Value](SYMBOL_TAG or new_id)
        symbols[].map[s] = symbols[].store.len
        symbols[].store.add(s)
    finally:
      release(SYMBOLS_LOCK)

proc to_key*(s: string): Key {.inline.} =
  cast[Key](to_symbol_value(s))

# Extract symbol index from Key for symbol table lookup
# Key is a symbol value cast to int64, so we need to extract the symbol index
proc symbol_index*(k: Key): int {.inline.} =
  int(cast[uint64](k) and PAYLOAD_MASK)
