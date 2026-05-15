{.push warning[ResultShadowed]: off.}
import std/[sysrand, tables]
import wrappers/openssl
import ../gene/vm/extension_abi

when defined(noExtensions):
  include ../gene/extension/boilerplate
else:
  import ../gene/types

const MaxDigestSize = 64

proc bytes_to_hex(bytes: openArray[byte]): string =
  const hex_chars = "0123456789abcdef"
  result = newStringOfCap(bytes.len * 2)
  for b in bytes:
    result.add(hex_chars[(b shr 4) and 0x0F])
    result.add(hex_chars[b and 0x0F])

proc value_to_string_arg(value: Value, context: string): string =
  if value.kind != VkString:
    raise new_exception(types.Exception, context & " requires a string")
  value.str

proc message_ptr(data: string): pointer =
  if data.len == 0:
    nil
  else:
    cast[pointer](unsafeAddr data[0])

proc evp_for_algorithm(name: string): EVP_MD =
  case name
  of "md5":
    EVP_md5()
  of "sha1":
    EVP_sha1()
  of "sha224":
    EVP_sha224()
  of "sha256":
    EVP_sha256()
  of "sha384":
    EVP_sha384()
  of "sha512":
    EVP_sha512()
  else:
    raise new_exception(types.Exception, "Unsupported digest algorithm: " & name)

proc digest_hex(algorithm, data: string): string =
  let md = evp_for_algorithm(algorithm)
  let ctx = EVP_MD_CTX_create()
  if ctx == nil:
    raise new_exception(types.Exception, "Failed to create digest context")
  defer: EVP_MD_CTX_destroy(ctx)

  if EVP_DigestInit_ex(ctx, md) != 1:
    raise new_exception(types.Exception, "Failed to initialize digest")
  if data.len > 0 and EVP_DigestUpdate(ctx, message_ptr(data), data.len.cuint) != 1:
    raise new_exception(types.Exception, "Failed to update digest")

  var digest: array[MaxDigestSize, byte]
  var digest_len: cuint = 0
  if EVP_DigestFinal_ex(ctx, addr digest[0], addr digest_len) != 1:
    raise new_exception(types.Exception, "Failed to finalize digest")
  bytes_to_hex(digest.toOpenArray(0, digest_len.int - 1))

proc hmac_hex(algorithm, key, data: string): string =
  let md = evp_for_algorithm(algorithm)
  var digest: array[MaxDigestSize, byte]
  var digest_len: cuint = 0
  let key_ptr =
    if key.len == 0: nil
    else: cast[pointer](unsafeAddr key[0])
  let msg_ptr =
    if data.len == 0: nil
    else: data.cstring

  let output = HMAC(
    md,
    key_ptr,
    key.len.cint,
    msg_ptr,
    data.len.csize_t,
    cast[cstring](addr digest[0]),
    addr digest_len
  )
  if output == nil:
    raise new_exception(types.Exception, "Failed to compute HMAC")
  bytes_to_hex(digest.toOpenArray(0, digest_len.int - 1))

proc secure_eq(a, b: string): bool =
  var diff = uint8(a.len xor b.len)
  let max_len = max(a.len, b.len)
  for i in 0..<max_len:
    let left =
      if i < a.len: cast[uint8](a[i])
      else: 0'u8
    let right =
      if i < b.len: cast[uint8](b[i])
      else: 0'u8
    diff = diff or (left xor right)
  diff == 0'u8

proc vm_digest_algorithm(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                         arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 2:
    raise new_exception(types.Exception, "digest requires algorithm and data")
  let algorithm = value_to_string_arg(get_positional_arg(args, 0, has_keyword_args), "digest algorithm")
  let data = value_to_string_arg(get_positional_arg(args, 1, has_keyword_args), "digest data")
  digest_hex(algorithm, data).to_value()

proc vm_hash_value(args: ptr UncheckedArray[Value], arg_count: int,
                   has_keyword_args: bool, algorithm: string): Value =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, algorithm & " requires data")
  let data = value_to_string_arg(get_positional_arg(args, 0, has_keyword_args), algorithm & " data")
  digest_hex(algorithm, data).to_value()

proc vm_md5(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
            arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  vm_hash_value(args, arg_count, has_keyword_args, "md5")

proc vm_sha1(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
             arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  vm_hash_value(args, arg_count, has_keyword_args, "sha1")

proc vm_sha224(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
               arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  vm_hash_value(args, arg_count, has_keyword_args, "sha224")

proc vm_sha256(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
               arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  vm_hash_value(args, arg_count, has_keyword_args, "sha256")

proc vm_sha384(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
               arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  vm_hash_value(args, arg_count, has_keyword_args, "sha384")

proc vm_sha512(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
               arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  vm_hash_value(args, arg_count, has_keyword_args, "sha512")

proc vm_hmac_algorithm(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                       arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 3:
    raise new_exception(types.Exception, "hmac requires algorithm, key, and data")
  let algorithm = value_to_string_arg(get_positional_arg(args, 0, has_keyword_args), "hmac algorithm")
  let key = value_to_string_arg(get_positional_arg(args, 1, has_keyword_args), "hmac key")
  let data = value_to_string_arg(get_positional_arg(args, 2, has_keyword_args), "hmac data")
  hmac_hex(algorithm, key, data).to_value()

proc vm_hmac_sha256(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                    arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 2:
    raise new_exception(types.Exception, "hmac_sha256 requires key and data")
  let key = value_to_string_arg(get_positional_arg(args, 0, has_keyword_args), "hmac_sha256 key")
  let data = value_to_string_arg(get_positional_arg(args, 1, has_keyword_args), "hmac_sha256 data")
  hmac_hex("sha256", key, data).to_value()

proc vm_random_bytes(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                     arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "random_bytes requires a byte count")
  let count_val = get_positional_arg(args, 0, has_keyword_args)
  if count_val.kind != VkInt:
    raise new_exception(types.Exception, "random_bytes count must be an integer")
  let count = count_val.to_int()
  if count < 0 or count > 1_048_576:
    raise new_exception(types.Exception, "random_bytes count must be between 0 and 1048576")
  let bytes = urandom(count.int)
  var raw = newStringOfCap(bytes.len)
  for b in bytes:
    raw.add(char(b))
  raw.to_value()

proc vm_random_hex(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                   arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "random_hex requires a byte count")
  let count_val = get_positional_arg(args, 0, has_keyword_args)
  if count_val.kind != VkInt:
    raise new_exception(types.Exception, "random_hex count must be an integer")
  let count = count_val.to_int()
  if count < 0 or count > 1_048_576:
    raise new_exception(types.Exception, "random_hex count must be between 0 and 1048576")
  let bytes = urandom(count.int)
  bytes_to_hex(bytes).to_value()

proc vm_secure_eq(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                  arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 2:
    raise new_exception(types.Exception, "secure_eq requires two strings")
  let a = value_to_string_arg(get_positional_arg(args, 0, has_keyword_args), "secure_eq first argument")
  let b = value_to_string_arg(get_positional_arg(args, 1, has_keyword_args), "secure_eq second argument")
  secure_eq(a, b).to_value()

proc put_fn(ns: Namespace, name: string, fn: NativeFn) =
  let fn_ref = new_ref(VkNativeFn)
  fn_ref.native_fn = fn
  ns[name.to_key()] = fn_ref.to_ref_value()

proc build_crypto_namespace(): Namespace =
  result = new_namespace("crypto")
  put_fn(result, "digest", vm_digest_algorithm)
  put_fn(result, "hash", vm_digest_algorithm)
  put_fn(result, "md5", vm_md5)
  put_fn(result, "sha1", vm_sha1)
  put_fn(result, "sha224", vm_sha224)
  put_fn(result, "sha256", vm_sha256)
  put_fn(result, "sha384", vm_sha384)
  put_fn(result, "sha512", vm_sha512)
  put_fn(result, "hmac", vm_hmac_algorithm)
  put_fn(result, "hmac_sha256", vm_hmac_sha256)
  put_fn(result, "random_bytes", vm_random_bytes)
  put_fn(result, "random_hex", vm_random_hex)
  put_fn(result, "secure_eq", vm_secure_eq)
  put_fn(result, "constant_time_equal", vm_secure_eq)

proc init_crypto_namespace*() =
  VmCreatedCallbacks.add proc() {.gcsafe.} =
    if App == NIL or App.kind != VkApplication:
      return
    if App.app.genex_ns.kind == VkNamespace:
      {.cast(gcsafe).}:
        App.app.genex_ns.ref.ns["crypto".to_key()] = build_crypto_namespace().to_value()

init_crypto_namespace()

proc init*(vm: ptr VirtualMachine): Namespace {.gcsafe.} =
  discard vm
  if App == NIL or App.kind != VkApplication:
    return nil
  if App.app.genex_ns.kind != VkNamespace:
    return nil
  let crypto_val = App.app.genex_ns.ref.ns.members.getOrDefault("crypto".to_key(), NIL)
  if crypto_val.kind == VkNamespace:
    return crypto_val.ref.ns
  nil

proc gene_init*(host: ptr GeneHostAbi): int32 {.cdecl, exportc, dynlib.} =
  if host == nil:
    return int32(GeneExtErr)
  if host.abi_version != GENE_EXT_ABI_VERSION:
    return int32(GeneExtAbiMismatch)
  let vm = apply_extension_host_context(host)
  run_extension_vm_created_callbacks()
  let ns = init(vm)
  if host.result_namespace != nil:
    host.result_namespace[] = ns
  if ns == nil:
    return int32(GeneExtErr)
  int32(GeneExtOk)

{.pop.}
