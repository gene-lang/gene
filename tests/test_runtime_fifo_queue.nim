import std/[options, os, unittest]

import gene/vm/fifo_queue
import gene/vm/thread

proc channelBlockingSender(ch: thread.Channel[int]) {.thread.} =
  ch.send(10)
  ch.send(20)

suite "Runtime FIFO queue":
  test "FIFO preserves ordering across compaction and later appends":
    var queue = initFifoQueue[int](4)

    check queue.len == 0
    check queue.isEmpty
    expect IndexDefect:
      discard queue.peekFront()
    expect IndexDefect:
      discard queue.popFront()

    for i in 0..<90:
      queue.add(i)

    check queue.peekFront() == 0
    for i in 0..<70:
      check queue.popFront() == i

    for i in 90..<140:
      queue.add(i)

    var expected = 70
    for item in queue:
      check item == expected
      expected.inc()
    check expected == 140

    expected = 70
    while queue.len > 0:
      check queue.popFront() == expected
      expected.inc()
    check expected == 140
    check queue.isEmpty

  test "capacity helpers and clear preserve empty boundary behavior":
    var queue = initFifoQueue[string](2)

    check queue.hasCapacity(2)
    check not queue.isFull(2)

    queue.add("first")
    queue.add("second")
    check queue.len == 2
    check queue.isFull(2)
    check not queue.hasCapacity(2)

    check queue.popFront() == "first"
    check queue.hasCapacity(2)

    queue.add("third")
    check queue.popFront() == "second"
    check queue.popFront() == "third"

    queue.add("after-clear")
    queue.clear()
    check queue.len == 0
    check queue.isEmpty
    expect IndexDefect:
      discard queue.popFront()

  test "thread channel try_recv is empty-safe and receive order is FIFO":
    var ch: thread.Channel[int]
    ch.open(3)

    check ch.try_recv().isNone

    ch.send(1)
    ch.send(2)
    ch.send(3)

    let first = ch.try_recv()
    check first.isSome
    check first.get() == 1

    ch.send(4)
    check ch.recv() == 2
    check ch.recv() == 3
    check ch.recv() == 4
    check ch.try_recv().isNone

    ch.close()

  test "thread channel capacity blocks producer until receive frees space":
    var ch: thread.Channel[int]
    ch.open(1)
    var worker: Thread[thread.Channel[int]]

    createThread(worker, channelBlockingSender, ch)
    sleep(50)

    check ch.recv() == 10
    joinThread(worker)
    check ch.recv() == 20
    check ch.try_recv().isNone

    ch.close()
