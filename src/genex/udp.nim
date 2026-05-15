{.push warning[ResultShadowed]: off.}
import std/[net, locks, tables]
import ../gene/vm/extension_abi

when defined(noExtensions):
  include ../gene/extension/boilerplate
else:
  import ../gene/types

type
  UdpSocketHandle = ref object
    socket: Socket
    closed: bool
    address: string
    port: int

var udp_socket_class_global: Class
var udp_sockets: Table[system.int64, UdpSocketHandle] = initTable[system.int64, UdpSocketHandle]()
var next_udp_socket_id: system.int64 = 1
var udp_lock: Lock
initLock(udp_lock)

proc int_arg(value: Value, context: string): int =
  if value.kind != VkInt:
    raise new_exception(types.Exception, context & " must be an integer")
  value.to_int().int

proc string_arg(value: Value, context: string): string =
  if value.kind != VkString:
    raise new_exception(types.Exception, context & " must be a string")
  value.str

proc register_udp_socket(handle: UdpSocketHandle): Value =
  var id: system.int64
  {.cast(gcsafe).}:
    withLock(udp_lock):
      id = next_udp_socket_id
      next_udp_socket_id += 1
      udp_sockets[id] = handle

  let cls = block:
    {.cast(gcsafe).}:
      if udp_socket_class_global != nil: udp_socket_class_global else: new_class("UdpSocket")
  result = new_instance_value(cls)
  instance_props(result)["__udp_socket_id__".to_key()] = id.to_value()
  instance_props(result)["address".to_key()] = handle.address.to_value()
  instance_props(result)["port".to_key()] = handle.port.to_value()

proc udp_socket_handle(self: Value): UdpSocketHandle =
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "UDP method requires a UdpSocket instance")
  let id_val = instance_props(self).getOrDefault("__udp_socket_id__".to_key(), NIL)
  if id_val.kind != VkInt:
    raise new_exception(types.Exception, "Invalid UdpSocket instance")
  let id = id_val.to_int()
  {.cast(gcsafe).}:
    withLock(udp_lock):
      if not udp_sockets.hasKey(id):
        raise new_exception(types.Exception, "UdpSocket not found")
      result = udp_sockets[id]
  if result.closed:
    raise new_exception(types.Exception, "UdpSocket is closed")

proc vm_udp_open(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                 has_keyword_args: bool): Value {.gcsafe.} =
  let positional = get_positional_count(arg_count, has_keyword_args)
  let port =
    if positional > 0:
      int_arg(get_positional_arg(args, 0, has_keyword_args), "udp/open port")
    else:
      0
  let address =
    if positional > 1:
      string_arg(get_positional_arg(args, 1, has_keyword_args), "udp/open address")
    else:
      ""
  if port < 0:
    raise new_exception(types.Exception, "udp/open port must be non-negative")

  try:
    let socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, buffered = false)
    socket.setSockOpt(OptReuseAddr, true)
    if has_keyword_args:
      let broadcast_val = get_keyword_arg(args, "broadcast")
      if broadcast_val != NIL and broadcast_val.to_bool():
        socket.setSockOpt(OptBroadcast, true)
    socket.bindAddr(Port(port), address)
    register_udp_socket(UdpSocketHandle(socket: socket, closed: false, address: address, port: port))
  except CatchableError as e:
    raise new_exception(types.Exception, "UDP open failed: " & e.msg)

proc udp_socket_send_to(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                        has_keyword_args: bool): Value {.gcsafe.} =
  if get_method_arg_count(arg_count, has_keyword_args) < 3:
    raise new_exception(types.Exception, "UdpSocket.send_to requires host, port, and data")
  let self = get_self(args, has_keyword_args)
  let handle = udp_socket_handle(self)
  let host = string_arg(get_method_arg(args, 0, has_keyword_args), "UdpSocket.send_to host")
  let port = int_arg(get_method_arg(args, 1, has_keyword_args), "UdpSocket.send_to port")
  let data = string_arg(get_method_arg(args, 2, has_keyword_args), "UdpSocket.send_to data")
  try:
    handle.socket.sendTo(host, Port(port), data)
    NIL
  except CatchableError as e:
    raise new_exception(types.Exception, "UDP send_to failed: " & e.msg)

proc udp_socket_recv_from(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                          has_keyword_args: bool): Value {.gcsafe.} =
  if get_method_arg_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "UdpSocket.recv_from requires size")
  let self = get_self(args, has_keyword_args)
  let handle = udp_socket_handle(self)
  let size = int_arg(get_method_arg(args, 0, has_keyword_args), "UdpSocket.recv_from size")
  if size < 0:
    raise new_exception(types.Exception, "UdpSocket.recv_from size must be non-negative")
  try:
    var body = ""
    var address = ""
    var port = Port(0)
    discard handle.socket.recvFrom(body, size, address, port)
    var result_map = new_map_value()
    map_data(result_map)["body".to_key()] = body.to_value()
    map_data(result_map)["address".to_key()] = address.to_value()
    map_data(result_map)["port".to_key()] = int(port).to_value()
    result_map
  except CatchableError as e:
    raise new_exception(types.Exception, "UDP recv_from failed: " & e.msg)

proc udp_socket_close(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                      has_keyword_args: bool): Value {.gcsafe.} =
  let self = get_self(args, has_keyword_args)
  let handle = udp_socket_handle(self)
  try:
    handle.socket.close()
    handle.closed = true
    NIL
  except CatchableError as e:
    raise new_exception(types.Exception, "UDP close failed: " & e.msg)

proc put_fn(ns: Namespace, name: string, fn: NativeFn) =
  let fn_ref = new_ref(VkNativeFn)
  fn_ref.native_fn = fn
  ns[name.to_key()] = fn_ref.to_ref_value()

proc build_udp_namespace(): Namespace =
  result = new_namespace("udp")
  put_fn(result, "open", vm_udp_open)

  udp_socket_class_global = new_class("UdpSocket")
  udp_socket_class_global.def_native_method("send_to", udp_socket_send_to)
  udp_socket_class_global.def_native_method("recv_from", udp_socket_recv_from)
  udp_socket_class_global.def_native_method("close", udp_socket_close)
  let socket_ref = new_ref(VkClass)
  socket_ref.class = udp_socket_class_global
  result["UdpSocket".to_key()] = socket_ref.to_ref_value()

proc init_udp_namespace*() =
  VmCreatedCallbacks.add proc() {.gcsafe.} =
    if App == NIL or App.kind != VkApplication:
      return
    if App.app.genex_ns.kind == VkNamespace:
      {.cast(gcsafe).}:
        App.app.genex_ns.ref.ns["udp".to_key()] = build_udp_namespace().to_value()

init_udp_namespace()

proc init*(vm: ptr VirtualMachine): Namespace {.gcsafe.} =
  discard vm
  if App == NIL or App.kind != VkApplication:
    return nil
  if App.app.genex_ns.kind != VkNamespace:
    return nil
  let udp_val = App.app.genex_ns.ref.ns.members.getOrDefault("udp".to_key(), NIL)
  if udp_val.kind == VkNamespace:
    return udp_val.ref.ns
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
