import unittest
import std/tables
import ./helpers
import gene/types except Exception

test_vm """
  (gene/json/parse "{\"a\": true}")
""", proc(result: Value) =
  check result.kind == VkMap
  let key = "a".to_key()
  check result.ref.map.hasKey(key)
  check result.ref.map[key].to_bool

test_vm """
  ([1 2].to_json)
""", "[1,2]"
