import tables

import ./types
import ./hash_map_support

proc hash_set_count*(hash_set: Value): int {.inline.} =
  hash_set_items(hash_set).len

proc rebuild_hash_set_index*(vm: ptr VirtualMachine, hash_set: Value) =
  if hash_set.kind != VkSet:
    not_allowed("Expected HashSet value")

  hash_set_buckets(hash_set).clear()
  for item_index, item in hash_set_items(hash_set):
    let bucket_hash = hash_map_value_hash(vm, item, "HashSet")
    if hash_set_buckets(hash_set).hasKey(bucket_hash):
      hash_set_buckets(hash_set)[bucket_hash].add(item_index)
    else:
      hash_set_buckets(hash_set)[bucket_hash] = @[item_index]

proc hash_set_find*(vm: ptr VirtualMachine, hash_set: Value, item: Value): int =
  if hash_set.kind != VkSet:
    not_allowed("Expected HashSet value")

  let bucket_hash = hash_map_value_hash(vm, item, "HashSet")
  let bucket = hash_set_buckets(hash_set).getOrDefault(bucket_hash, @[])
  for item_index in bucket:
    if item_index < hash_set_items(hash_set).len and hash_set_items(hash_set)[item_index] == item:
      return item_index
  return -1

proc hash_set_contains*(vm: ptr VirtualMachine, hash_set: Value, item: Value): bool {.inline.} =
  hash_set_find(vm, hash_set, item) >= 0

proc hash_set_add*(vm: ptr VirtualMachine, hash_set: Value, item: Value): bool =
  if hash_set.kind != VkSet:
    not_allowed("Expected HashSet value")

  if hash_set_find(vm, hash_set, item) >= 0:
    return false

  let bucket_hash = hash_map_value_hash(vm, item, "HashSet")
  let new_index = hash_set_items(hash_set).len
  hash_set_items(hash_set).add(item)
  if hash_set_buckets(hash_set).hasKey(bucket_hash):
    hash_set_buckets(hash_set)[bucket_hash].add(new_index)
  else:
    hash_set_buckets(hash_set)[bucket_hash] = @[new_index]
  true

proc hash_set_delete*(vm: ptr VirtualMachine, hash_set: Value, item: Value): tuple[found: bool, value: Value] =
  let item_index = hash_set_find(vm, hash_set, item)
  if item_index < 0:
    return (false, NIL)

  let removed = hash_set_items(hash_set)[item_index]
  hash_set_items(hash_set).delete(item_index)
  rebuild_hash_set_index(vm, hash_set)
  (true, removed)
