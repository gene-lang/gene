import hashes, tables

import ./types

proc hash_map_pair_count*(hash_map: Value): int {.inline.} =
  hash_map_items(hash_map).len div 2

proc rebuild_hash_map_index*(hash_map: Value) =
  if hash_map.kind != VkHashMap:
    not_allowed("Expected HashMap value")

  hash_map_buckets(hash_map).clear()
  var pair_index = 0
  var i = 0
  while i + 1 < hash_map_items(hash_map).len:
    let key = hash_map_items(hash_map)[i]
    let bucket_hash = hash(key)
    if hash_map_buckets(hash_map).hasKey(bucket_hash):
      hash_map_buckets(hash_map)[bucket_hash].add(pair_index)
    else:
      hash_map_buckets(hash_map)[bucket_hash] = @[pair_index]
    inc(pair_index)
    i += 2

proc invoke_hash_method(vm: ptr VirtualMachine, key: Value, meth: Method): Value =
  case meth.callable.kind
  of VkFunction, VkBlock:
    return vm_exec_callable(vm, meth.callable, @[key])
  of VkNativeFn:
    return call_native_fn(meth.callable.ref.native_fn, vm, [key])
  of VkNativeMethod:
    return call_native_fn(meth.callable.ref.native_method, vm, [key])
  of VkBoundMethod:
    return vm_exec_callable(vm, meth.callable, @[])
  else:
    not_allowed("HashMap key hash method must be callable, got " & $meth.callable.kind)

proc hash_map_value_hash*(vm: ptr VirtualMachine, key: Value): Hash

proc structural_array_hash(vm: ptr VirtualMachine, key: Value): Hash =
  var result_hash: Hash = hash("Array")
  for item in array_data(key):
    result_hash = result_hash !& hash_map_value_hash(vm, item)
  !$result_hash

proc structural_map_hash(vm: ptr VirtualMachine, key: Value): Hash =
  var result_hash: Hash = hash("Map") !& hash(map_data(key).len)
  for map_key, map_value in map_data(key):
    var entry_hash: Hash = hash(map_key)
    entry_hash = entry_hash !& hash_map_value_hash(vm, map_value)
    result_hash = result_hash xor !$entry_hash
  !$result_hash

proc structural_hash_map_hash(vm: ptr VirtualMachine, key: Value): Hash =
  var result_hash: Hash = hash("HashMap") !& hash(hash_map_pair_count(key))
  var pair_index = 0
  while pair_index < hash_map_pair_count(key):
    let item_index = pair_index * 2
    var entry_hash = hash_map_value_hash(vm, hash_map_items(key)[item_index])
    if item_index + 1 < hash_map_items(key).len:
      entry_hash = entry_hash !& hash_map_value_hash(vm, hash_map_items(key)[item_index + 1])
    result_hash = result_hash xor !$entry_hash
    inc(pair_index)
  !$result_hash

proc hash_map_value_hash*(vm: ptr VirtualMachine, key: Value): Hash =
  case key.kind
  of VkNil:
    hash("Nil")
  of VkVoid:
    hash("Void")
  of VkPlaceholder:
    hash("Placeholder")
  of VkBool:
    hash(key == TRUE)
  of VkInt:
    hash(key.to_int())
  of VkFloat:
    hash(cast[uint64](key))
  of VkChar:
    hash(cast[uint64](key))
  of VkString:
    hash(key.str)
  of VkSymbol:
    hash(key.str)
  of VkComplexSymbol:
    hash(key.ref.csymbol)
  of VkArray:
    structural_array_hash(vm, key)
  of VkMap:
    structural_map_hash(vm, key)
  of VkHashMap:
    structural_hash_map_hash(vm, key)
  else:
    let key_class = key.get_class()
    if key_class.is_nil:
      not_allowed("Key is not hashable for HashMap: " & $key.kind)

    let hash_method = key_class.get_method("hash")
    if hash_method.is_nil:
      not_allowed("Key is not hashable for HashMap: " & $key.kind)

    let hash_value = invoke_hash_method(vm, key, hash_method)
    if hash_value.kind != VkInt:
      not_allowed("HashMap key .hash must return Int, got " & $hash_value.kind)
    hash(hash_value.to_int())

proc hash_map_find_pair*(vm: ptr VirtualMachine, hash_map: Value, key: Value): int =
  if hash_map.kind != VkHashMap:
    not_allowed("Expected HashMap value")

  let bucket_hash = hash_map_value_hash(vm, key)
  let bucket = hash_map_buckets(hash_map).getOrDefault(bucket_hash, @[])
  for pair_index in bucket:
    let item_index = pair_index * 2
    if item_index < hash_map_items(hash_map).len and hash_map_items(hash_map)[item_index] == key:
      return pair_index
  return -1

proc hash_map_put*(vm: ptr VirtualMachine, hash_map: Value, key: Value, value: Value) =
  if hash_map.kind != VkHashMap:
    not_allowed("Expected HashMap value")

  let pair_index = hash_map_find_pair(vm, hash_map, key)
  if pair_index >= 0:
    hash_map_items(hash_map)[pair_index * 2 + 1] = value
    return

  let bucket_hash = hash_map_value_hash(vm, key)
  let new_pair_index = hash_map_pair_count(hash_map)
  hash_map_items(hash_map).add(key)
  hash_map_items(hash_map).add(value)
  if hash_map_buckets(hash_map).hasKey(bucket_hash):
    hash_map_buckets(hash_map)[bucket_hash].add(new_pair_index)
  else:
    hash_map_buckets(hash_map)[bucket_hash] = @[new_pair_index]

proc hash_map_get*(vm: ptr VirtualMachine, hash_map: Value, key: Value): tuple[found: bool, value: Value] =
  let pair_index = hash_map_find_pair(vm, hash_map, key)
  if pair_index < 0:
    return (false, NIL)
  let item_index = pair_index * 2
  (true, hash_map_items(hash_map)[item_index + 1])

proc hash_map_delete*(vm: ptr VirtualMachine, hash_map: Value, key: Value): tuple[found: bool, value: Value] =
  let pair_index = hash_map_find_pair(vm, hash_map, key)
  if pair_index < 0:
    return (false, NIL)

  let item_index = pair_index * 2
  let removed = hash_map_items(hash_map)[item_index + 1]
  hash_map_items(hash_map).delete(item_index + 1)
  hash_map_items(hash_map).delete(item_index)
  rebuild_hash_map_index(hash_map)
  (true, removed)
