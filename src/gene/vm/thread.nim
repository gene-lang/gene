import locks, random
import ../types

# Simple channel implementation for MVP
type
  Channel*[T] = ptr ChannelObj[T]

  ChannelObj*[T] = object
    lock: Lock
    cond: Cond
    data: seq[T]
    capacity: int
    closed: bool

proc open*[T](ch: var Channel[T], capacity: int) =
  if ch != nil:
    return  # Already opened
  ch = cast[Channel[T]](alloc0(sizeof(ChannelObj[T])))
  initLock(ch.lock)
  initCond(ch.cond)
  ch.data = newSeq[T](0)
  ch.capacity = capacity
  ch.closed = false

proc close*[T](ch: Channel[T]) =
  if ch == nil:
    return
  acquire(ch.lock)
  ch.closed = true
  broadcast(ch.cond)
  release(ch.lock)

proc send*[T](ch: Channel[T], item: T) =
  acquire(ch.lock)

  # Wait if full
  while ch.data.len >= ch.capacity and not ch.closed:
    wait(ch.cond, ch.lock)

  if not ch.closed:
    ch.data.add(item)
    signal(ch.cond)

  release(ch.lock)

proc recv*[T](ch: Channel[T]): T =
  acquire(ch.lock)

  # Wait for data
  while ch.data.len == 0 and not ch.closed:
    wait(ch.cond, ch.lock)

  if ch.data.len > 0:
    result = ch.data[0]
    ch.data.delete(0)
    signal(ch.cond)

  release(ch.lock)

# Thread-local channel and threading data
type
  ThreadChannel* = Channel[ThreadMessage]  # Store refs directly, not pointers

  ThreadDataObj* = object
    thread*: system.Thread[int]
    channel*: ThreadChannel

var THREAD_DATA*: array[0..MAX_THREADS, ThreadDataObj]  # Shared across threads (channels are thread-safe)

# Thread pool management
var thread_pool_lock: Lock
var next_message_id {.threadvar.}: int

proc init_thread_pool*() =
  ## Initialize the thread pool (call once from main thread)
  randomize()  # Initialize random number generator
  initLock(thread_pool_lock)

  # Initialize thread 0 as main thread
  THREADS[0].id = 0
  THREADS[0].secret = rand(int.high)
  THREADS[0].state = TsBusy
  THREADS[0].in_use = true
  THREADS[0].parent_id = 0
  THREADS[0].parent_secret = THREADS[0].secret

  THREAD_DATA[0].channel.open(CHANNEL_LIMIT)

  # Initialize other thread slots as free
  for i in 1..MAX_THREADS:
    THREADS[i].id = i
    THREADS[i].state = TsFree
    THREADS[i].in_use = false

proc get_free_thread*(): int =
  ## Find and allocate a free thread slot
  ## Returns -1 if no threads available
  acquire(thread_pool_lock)
  defer: release(thread_pool_lock)

  for i in 1..MAX_THREADS:
    if not THREADS[i].in_use and THREADS[i].state == TsFree:
      THREADS[i].in_use = true
      THREADS[i].state = TsBusy
      THREADS[i].secret = rand(int.high)
      return i
  return -1

proc init_thread*(thread_id: int, parent_id: int = 0) =
  ## Initialize thread metadata
  THREADS[thread_id].id = thread_id
  THREADS[thread_id].parent_id = parent_id
  THREADS[thread_id].parent_secret = THREADS[parent_id].secret
  THREADS[thread_id].state = TsBusy

  # Open channel for this thread
  THREAD_DATA[thread_id].channel.open(CHANNEL_LIMIT)

proc cleanup_thread*(thread_id: int) =
  ## Clean up thread and mark as free
  acquire(thread_pool_lock)
  defer: release(thread_pool_lock)

  THREADS[thread_id].state = TsFree
  THREADS[thread_id].in_use = false
  THREADS[thread_id].secret = rand(int.high)  # Rotate secret

  # Close channel
  THREAD_DATA[thread_id].channel.close()

# VM state reset
proc reset_vm_state*() =
  ## Reset VM state for thread reuse
  VM.pc = 0
  VM.cu = nil
  VM.trace = false

  # Return all frames to pool
  var current_frame = VM.frame
  while current_frame != nil:
    let caller = current_frame.caller_frame
    current_frame.free()
    current_frame = caller
  VM.frame = nil

  # Clear exception handlers
  VM.exception_handlers.setLen(0)
  VM.current_exception = NIL

  # Clear generator state
  VM.current_generator = nil

# Thread pool initialization must be called from main thread
# This will be called from vm.nim
