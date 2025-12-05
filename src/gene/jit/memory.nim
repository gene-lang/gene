import strformat

when defined(posix):
  import posix
elif defined(windows):
  import winlean

import ../types
import ../types/type_defs

const PAGE_SIZE = 4096

proc page_align(size: int): int =
  ## Round up to the nearest page.
  (size + PAGE_SIZE - 1) and not (PAGE_SIZE - 1)

when defined(posix):
  proc allocate_executable_memory*(size: int): pointer =
    ## Allocate RW pages for JIT; caller must mark RX later.
    let alloc_size = page_align(size)
    var flags = MAP_PRIVATE or MAP_ANONYMOUS
    when defined(macosx):
      when declared(MAP_JIT):
        flags = flags or MAP_JIT
      else:
        const MAP_JIT = 0x800'i32
        flags = flags or MAP_JIT
    let mem = mmap(nil, alloc_size, PROT_READ or PROT_WRITE, flags, -1, 0)
    if mem == MAP_FAILED:
      raise new_exception(types.Exception, fmt"JIT mmap failed for {alloc_size} bytes")
    mem

  proc make_executable*(mem: pointer, size: int) =
    ## Flip pages to RX (no write) after code emission.
    let alloc_size = page_align(size)
    if mprotect(mem, alloc_size, PROT_READ or PROT_EXEC) != 0:
      raise new_exception(types.Exception, fmt"JIT mprotect RX failed for {alloc_size} bytes")
    when defined(arm64):
      # Flush the instruction cache for freshly generated code.
      proc clear_cache(start, finish: cstring) {.importc: "__builtin___clear_cache", noSideEffect.}
      clear_cache(cast[cstring](mem), cast[cstring](cast[uint](mem) + alloc_size.uint))

  proc free_executable_memory*(mem: pointer, size: int) =
    let alloc_size = page_align(size)
    discard munmap(mem, alloc_size)

elif defined(windows):
  proc allocate_executable_memory*(size: int): pointer =
    let alloc_size = page_align(size)
    result = VirtualAlloc(nil, alloc_size, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE)
    if result == nil:
      raise new_exception(types.Exception, fmt"JIT VirtualAlloc failed for {alloc_size} bytes")

  proc make_executable*(mem: pointer, size: int) =
    let alloc_size = page_align(size)
    var old_protect: DWORD
    if VirtualProtect(mem, alloc_size, PAGE_EXECUTE_READ, old_protect.addr) == 0:
      raise new_exception(types.Exception, fmt"JIT VirtualProtect RX failed for {alloc_size} bytes")

  proc free_executable_memory*(mem: pointer, size: int) =
    discard VirtualFree(mem, 0, MEM_RELEASE)

else:
  # Fallback stubs for unsupported targets; keep interpreter-only behavior.
  proc allocate_executable_memory*(size: int): pointer =
    raise new_exception(types.Exception, "JIT executable memory not supported on this platform")

  proc make_executable*(mem: pointer, size: int) =
    discard

  proc free_executable_memory*(mem: pointer, size: int) =
    discard
