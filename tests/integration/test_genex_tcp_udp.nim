import std/[net, tables, unittest]

import ../helpers
import gene/types except Exception
import gene/vm

proc free_udp_port(): int =
  let socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, buffered = false)
  try:
    socket.bindAddr(Port(0), "127.0.0.1")
    let (_, port) = socket.getLocalAddr()
    result = int(port)
  finally:
    socket.close()

suite "TCP and UDP extensions":
  test "TCP can connect to a loopback listener and close":
    init_all_with_extensions()

    let listener = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    listener.setSockOpt(OptReuseAddr, true)
    listener.bindAddr(Port(0), "127.0.0.1")
    listener.listen()
    let (_, port) = listener.getLocalAddr()

    try:
      let result = VM.exec("""
        (var sock (genex/tcp/connect "127.0.0.1" """ & $int(port) & """ ^timeout_ms 2000))
        (sock .close)
        true
      """, "genex_tcp_connect.gene")
      check result.to_bool == true
    finally:
      listener.close()

  test "TCP listen returns a closable server":
    init_all_with_extensions()

    let result = VM.exec("""
      (var server (genex/tcp/listen 0 "127.0.0.1"))
      (server .close)
      true
    """, "genex_tcp_listen.gene")
    check result.to_bool == true

  test "UDP can send a datagram to itself and receive peer metadata":
    init_all_with_extensions()

    let port = free_udp_port()
    let result = VM.exec("""
      (var sock (genex/udp/open """ & $port & """ "127.0.0.1"))
      (sock .send_to "127.0.0.1" """ & $port & """ "ping")
      (var packet (sock .recv_from 64))
      (sock .close)
      packet
    """, "genex_udp_loopback.gene")

    check result.kind == VkMap
    let packet = map_data(result)
    check packet["body".to_key()].str == "ping"
    check packet["address".to_key()].str.len > 0
    check packet["port".to_key()].kind == VkInt
