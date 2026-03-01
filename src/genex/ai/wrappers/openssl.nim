## Minimal OpenSSL bindings for HMAC-SHA256 used by control_slack.nim
## Uses compile-time linking to avoid macOS SIP dynamic loading issues.

const
  EVP_MAX_MD_SIZE* = 64  # SHA-512 digest length; SHA-256 uses 32

when defined(macosx):
  {.passC: "-I/opt/homebrew/opt/openssl@3/include".}
  {.passL: "-L/opt/homebrew/opt/openssl@3/lib -lcrypto".}
elif defined(windows):
  {.passL: "-lcrypto".}
else:
  {.passL: "-lcrypto".}

type
  EVP_MD* = pointer

proc EVP_sha256*(): EVP_MD {.cdecl, importc: "EVP_sha256".}

proc HMAC*(
  evp_md: EVP_MD;
  key: pointer;
  key_len: cint;
  data: cstring;
  data_len: csize_t;
  md: cstring;
  md_len: ptr cuint
): cstring {.cdecl, importc: "HMAC".}
