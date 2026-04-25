## Tiny FIFO queue for runtime hot paths.
##
## Front removals advance a head index instead of shifting the remaining
## elements on every dequeue. Storage is compacted only occasionally, so
## enqueue/dequeue are amortized O(1) while preserving simple seq-backed
## iteration for shutdown/error paths.

type
  FifoQueue*[T] = object
    storage: seq[T]
    head: int

proc initFifoQueue*[T](capacity: Natural = 0): FifoQueue[T] =
  if capacity > 0:
    result.storage = newSeqOfCap[T](capacity)
  else:
    result.storage = @[]
  result.head = 0

proc len*[T](queue: FifoQueue[T]): int {.inline.} =
  queue.storage.len - queue.head

proc isEmpty*[T](queue: FifoQueue[T]): bool {.inline.} =
  queue.len == 0

proc isFull*[T](queue: FifoQueue[T], capacity: int): bool {.inline.} =
  capacity >= 0 and queue.len >= capacity

proc hasCapacity*[T](queue: FifoQueue[T], capacity: int): bool {.inline.} =
  not queue.isFull(capacity)

proc compactIfNeeded[T](queue: var FifoQueue[T]) {.inline.} =
  let live = queue.len
  if queue.head == 0:
    return
  if live == 0:
    queue.storage.setLen(0)
    queue.head = 0
  elif queue.head >= 64 and queue.head * 2 >= queue.storage.len:
    var compacted = newSeqOfCap[T](live)
    for i in queue.head..<queue.storage.len:
      compacted.add(queue.storage[i])
    queue.storage = compacted
    queue.head = 0

proc add*[T](queue: var FifoQueue[T], item: T) {.inline.} =
  queue.storage.add(item)

proc peekFront*[T](queue: FifoQueue[T]): T {.inline.} =
  if queue.len == 0:
    raise newException(IndexDefect, "peekFront from empty FIFO queue")
  queue.storage[queue.head]

proc popFront*[T](queue: var FifoQueue[T]): T {.inline.} =
  if queue.len == 0:
    raise newException(IndexDefect, "popFront from empty FIFO queue")
  result = queue.storage[queue.head]
  queue.storage[queue.head] = default(T)
  queue.head.inc()
  queue.compactIfNeeded()

proc clear*[T](queue: var FifoQueue[T]) {.inline.} =
  queue.storage.setLen(0)
  queue.head = 0

iterator items*[T](queue: FifoQueue[T]): T =
  for i in queue.head..<queue.storage.len:
    yield queue.storage[i]
