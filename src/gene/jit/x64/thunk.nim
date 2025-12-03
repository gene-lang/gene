import system

import ../memory

type
  ThunkBuildResult* = object
    code*: pointer
    size*: int

proc build_jmp_thunk*(target: pointer): ThunkBuildResult =
  ## Build a tiny x86-64 thunk that jumps to `target`.
  ## Layout: movabs rax, imm64; jmp rax
  var bytes: seq[uint8] = @[
    0x48'u8, 0xB8'u8  # mov rax, imm64
  ]
  bytes.add(cast[array[8, uint8]](cast[uint64](target)))
  bytes.add(0xFF'u8)  # jmp rax
  bytes.add(0xE0'u8)

  let mem = allocate_executable_memory(bytes.len)
  copyMem(mem, bytes[0].unsafeAddr, bytes.len)
  make_executable(mem, bytes.len)
  ThunkBuildResult(code: mem, size: bytes.len)
