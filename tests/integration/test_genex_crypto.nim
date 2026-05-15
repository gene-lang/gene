import unittest

import ../helpers
import gene/types except Exception
import gene/vm

suite "Crypto extension":
  test "hashes, HMAC, random hex, and constant-time equality":
    init_all_with_extensions()

    let result = VM.exec("""
      [
        (genex/crypto/sha256 "abc")
        (genex/crypto/hmac_sha256 "key" "The quick brown fox jumps over the lazy dog")
        ((genex/crypto/random_hex 16) .size)
        (genex/crypto/secure_eq "same" "same")
        (genex/crypto/secure_eq "same" "different")
      ]
    """, "genex_crypto.gene")

    check result.kind == VkArray
    let values = array_data(result)
    check values.len == 5
    check values[0].str == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    check values[1].str == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
    check values[2].to_int == 32
    check values[3].to_bool == true
    check values[4].to_bool == false

  test "generic digest supports named algorithms":
    init_all_with_extensions()

    let result = VM.exec("""
      [
        (genex/crypto/digest "sha1" "abc")
        (genex/crypto/digest "sha512" "")
      ]
    """, "genex_crypto_digest.gene")

    check result.kind == VkArray
    let values = array_data(result)
    check values.len == 2
    check values[0].str == "a9993e364706816aba3e25717850c26c9cd0d89d"
    check values[1].str == "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce" &
      "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
