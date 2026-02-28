when defined(gene_wasm):
  discard
else:
  import os, times, random

when defined(gene_wasm):
  proc gene_host_now*(): int64 {.importc, cdecl.}
  proc gene_host_rand*(): int64 {.importc, cdecl.}
  proc gene_host_file_exists*(path: cstring): cint {.importc, cdecl.}
  proc gene_host_read_file*(path: cstring; out_buf: ptr cstring; out_len: ptr cint): cint {.importc, cdecl.}
  proc gene_host_write_file*(path: cstring; data: cstring; len: cint): cint {.importc, cdecl.}
  proc gene_host_free*(p: pointer) {.importc, cdecl.}

proc wasm_unsupported_message*(feature: string): string =
  "[GENE.WASM.UNSUPPORTED] " & feature & " is not available in wasm"

proc raise_wasm_unsupported*(feature: string) {.noreturn.} =
  raise newException(ValueError, wasm_unsupported_message(feature))

proc host_now_unix*(): int64 =
  when defined(gene_wasm):
    gene_host_now()
  else:
    epochTime().int64

proc host_now_us*(): int64 =
  when defined(gene_wasm):
    let now = gene_host_now()
    if now <= 0:
      0'i64
    else:
      now * 1_000_000'i64
  else:
    (epochTime() * 1_000_000).int64

proc host_rand_i64*(): int64 =
  when defined(gene_wasm):
    gene_host_rand()
  else:
    rand(int.high).int64

type
  HostReadResult* = tuple[ok: bool, content: string, error: string]
  HostWriteResult* = tuple[ok: bool, error: string]

proc host_file_exists*(path: string): bool =
  when defined(gene_wasm):
    gene_host_file_exists(path.cstring) != 0
  else:
    fileExists(path)

proc host_read_text_file*(path: string): HostReadResult =
  when defined(gene_wasm):
    var out_buf: cstring = nil
    var out_len: cint = 0
    let rc = gene_host_read_file(path.cstring, addr out_buf, addr out_len)
    if rc != 0:
      return (false, "", "host read failed")
    if out_len <= 0:
      if out_buf != nil:
        gene_host_free(cast[pointer](out_buf))
      return (true, "", "")
    if out_buf == nil:
      return (false, "", "host read returned nil buffer")

    var content = newString(out_len)
    copyMem(addr content[0], out_buf, out_len)
    gene_host_free(cast[pointer](out_buf))
    (true, content, "")
  else:
    try:
      (true, readFile(path), "")
    except CatchableError as e:
      (false, "", e.msg)

proc host_write_text_file*(path: string; content: string): HostWriteResult =
  when defined(gene_wasm):
    if gene_host_write_file(path.cstring, content.cstring, cint(content.len)) == 0:
      (true, "")
    else:
      (false, "host write failed")
  else:
    try:
      writeFile(path, content)
      (true, "")
    except CatchableError as e:
      (false, e.msg)
