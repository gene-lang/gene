{.push warning[ResultShadowed]: off.}
import std/[net, locks, tables]
import ../gene/vm/extension_abi

when defined(noExtensions):
  include ../gene/extension/boilerplate
else:
  import ../gene/types

type
  TcpSocketHandle = ref object
    socket: Socket
    closed: bool
    peer_address: string

  TcpServerHandle = ref object
    socket: Socket
    closed: bool
    address: string
    port: int

var socket_class_global: Class
var server_class_global: Class
var tcp_sockets: Table[system.int64, TcpSocketHandle] = initTable[system.int64, TcpSocketHandle]()
var tcp_servers: Table[system.int64, TcpServerHandle] = initTable[system.int64, TcpServerHandle]()
var next_socket_id: system.int64 = 1
var next_server_id: system.int64 = 1
var tcp_lock: Lock
initLock(tcp_lock)

proc int_arg(value: Value, context: string): int =
  if value.kind != VkInt:
    raise new_exception(types.Exception, context & " must be an integer")
  value.to_int().int

proc string_arg(value: Value, context: string): string =
  if value.kind != VkString:
    raise new_exception(types.Exception, context & " must be a string")
  value.str

proc timeout_arg(args: ptr UncheckedArray[Value], has_keyword_args: bool): int =
  result = -1
  if has_keyword_args:
    let timeout_val = get_keyword_arg(args, "timeout_ms")
    if timeout_val != NIL:
      result = int_arg(timeout_val, "^timeout_ms")
      if result < 0:
        raise new_exception(types.Exception, "^timeout_ms must be non-negative")

proc register_socket(handle: TcpSocketHandle): Value =
  var id: system.int64
  {.cast(gcsafe).}:
    withLock(tcp_lock):
      id = next_socket_id
      next_socket_id += 1
      tcp_sockets[id] = handle

  let cls = block:
    {.cast(gcsafe).}:
      if socket_class_global != nil: socket_class_global else: new_class("TcpSocket")
  result = new_instance_value(cls)
  instance_props(result)["__tcp_socket_id__".to_key()] = id.to_value()
  instance_props(result)["peer_address".to_key()] = handle.peer_address.to_value()

proc register_server(handle: TcpServerHandle): Value =
  var id: system.int64
  {.cast(gcsafe).}:
    withLock(tcp_lock):
      id = next_server_id
      next_server_id += 1
      tcp_servers[id] = handle

  let cls = block:
    {.cast(gcsafe).}:
      if server_class_global != nil: server_class_global else: new_class("TcpServer")
  result = new_instance_value(cls)
  instance_props(result)["__tcp_server_id__".to_key()] = id.to_value()
  instance_props(result)["address".to_key()] = handle.address.to_value()
  instance_props(result)["port".to_key()] = handle.port.to_value()

proc socket_handle(self: Value): TcpSocketHandle =
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "TCP socket method requires a TcpSocket instance")
  let id_val = instance_props(self).getOrDefault("__tcp_socket_id__".to_key(), NIL)
  if id_val.kind != VkInt:
    raise new_exception(types.Exception, "Invalid TcpSocket instance")
  let id = id_val.to_int()
  {.cast(gcsafe).}:
    withLock(tcp_lock):
      if not tcp_sockets.hasKey(id):
        raise new_exception(types.Exception, "TcpSocket not found")
      result = tcp_sockets[id]
  if result.closed:
    raise new_exception(types.Exception, "TcpSocket is closed")

proc server_handle(self: Value): TcpServerHandle =
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "TCP server method requires a TcpServer instance")
  let id_val = instance_props(self).getOrDefault("__tcp_server_id__".to_key(), NIL)
  if id_val.kind != VkInt:
    raise new_exception(types.Exception, "Invalid TcpServer instance")
  let id = id_val.to_int()
  {.cast(gcsafe).}:
    withLock(tcp_lock):
      if not tcp_servers.hasKey(id):
        raise new_exception(types.Exception, "TcpServer not found")
      result = tcp_servers[id]
  if result.closed:
    raise new_exception(types.Exception, "TcpServer is closed")

proc vm_tcp_connect(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                    has_keyword_args: bool): Value {.gcsafe.} =
  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional < 2:
    raise new_exception(types.Exception, "tcp/connect requires host and port")
  let host = string_arg(get_positional_arg(args, 0, has_keyword_args), "tcp/connect host")
  let port = int_arg(get_positional_arg(args, 1, has_keyword_args), "tcp/connect port")
  let timeout_ms = timeout_arg(args, has_keyword_args)

  try:
    let socket = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if timeout_ms >= 0:
      socket.connect(host, Port(port), timeout_ms)
    else:
      socket.connect(host, Port(port))
    register_socket(TcpSocketHandle(socket: socket, closed: false, peer_address: host & ":" & $port))
  except CatchableError as e:
    raise new_exception(types.Exception, "TCP connect failed: " & e.msg)

proc vm_tcp_listen(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                   has_keyword_args: bool): Value {.gcsafe.} =
  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional < 1:
    raise new_exception(types.Exception, "tcp/listen requires a port")
  let port = int_arg(get_positional_arg(args, 0, has_keyword_args), "tcp/listen port")
  let address =
    if positional > 1:
      string_arg(get_positional_arg(args, 1, has_keyword_args), "tcp/listen address")
    else:
      ""
  var backlog = 128
  if has_keyword_args:
    let backlog_val = get_keyword_arg(args, "backlog")
    if backlog_val != NIL:
      backlog = int_arg(backlog_val, "^backlog")
      if backlog <= 0:
        raise new_exception(types.Exception, "^backlog must be positive")

  try:
    let socket = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    socket.setSockOpt(OptReuseAddr, true)
    when declared(OptReusePort):
      try:
        socket.setSockOpt(OptReusePort, true)
      except CatchableError:
        discard
    socket.bindAddr(Port(port), address)
    socket.listen(backlog.cint)
    register_server(TcpServerHandle(socket: socket, closed: false, address: address, port: port))
  except CatchableError as e:
    raise new_exception(types.Exception, "TCP listen failed: " & e.msg)

proc tcp_socket_send(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                     has_keyword_args: bool): Value {.gcsafe.} =
  if get_method_arg_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "TcpSocket.send requires data")
  let self = get_self(args, has_keyword_args)
  let handle = socket_handle(self)
  let data = string_arg(get_method_arg(args, 0, has_keyword_args), "TcpSocket.send data")
  try:
    handle.socket.send(data)
    NIL
  except CatchableError as e:
    raise new_exception(types.Exception, "TCP send failed: " & e.msg)

proc tcp_socket_recv(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                     has_keyword_args: bool): Value {.gcsafe.} =
  if get_method_arg_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "TcpSocket.recv requires size")
  let self = get_self(args, has_keyword_args)
  let handle = socket_handle(self)
  let size = int_arg(get_method_arg(args, 0, has_keyword_args), "TcpSocket.recv size")
  if size < 0:
    raise new_exception(types.Exception, "TcpSocket.recv size must be non-negative")
  let timeout_ms = timeout_arg(args, has_keyword_args)
  try:
    handle.socket.recv(size, timeout_ms).to_value()
  except TimeoutError:
    NIL
  except CatchableError as e:
    raise new_exception(types.Exception, "TCP recv failed: " & e.msg)

proc tcp_socket_recv_line(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                          has_keyword_args: bool): Value {.gcsafe.} =
  let self = get_self(args, has_keyword_args)
  let handle = socket_handle(self)
  let timeout_ms = timeout_arg(args, has_keyword_args)
  try:
    handle.socket.recvLine(timeout_ms).to_value()
  except TimeoutError:
    NIL
  except CatchableError as e:
    raise new_exception(types.Exception, "TCP recv_line failed: " & e.msg)

proc tcp_socket_close(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                      has_keyword_args: bool): Value {.gcsafe.} =
  let self = get_self(args, has_keyword_args)
  let handle = socket_handle(self)
  try:
    handle.socket.close()
    handle.closed = true
    NIL
  except CatchableError as e:
    raise new_exception(types.Exception, "TCP close failed: " & e.msg)

proc tcp_server_accept(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                       has_keyword_args: bool): Value {.gcsafe.} =
  let self = get_self(args, has_keyword_args)
  let handle = server_handle(self)
  try:
    var client: Socket
    var address = ""
    handle.socket.acceptAddr(client, address)
    register_socket(TcpSocketHandle(socket: client, closed: false, peer_address: address))
  except CatchableError as e:
    raise new_exception(types.Exception, "TCP accept failed: " & e.msg)

proc tcp_server_close(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                      has_keyword_args: bool): Value {.gcsafe.} =
  let self = get_self(args, has_keyword_args)
  let handle = server_handle(self)
  try:
    handle.socket.close()
    handle.closed = true
    NIL
  except CatchableError as e:
    raise new_exception(types.Exception, "TCP server close failed: " & e.msg)

proc put_fn(ns: Namespace, name: string, fn: NativeFn) =
  let fn_ref = new_ref(VkNativeFn)
  fn_ref.native_fn = fn
  ns[name.to_key()] = fn_ref.to_ref_value()

proc build_tcp_namespace(): Namespace =
  result = new_namespace("tcp")
  put_fn(result, "connect", vm_tcp_connect)
  put_fn(result, "listen", vm_tcp_listen)

  socket_class_global = new_class("TcpSocket")
  socket_class_global.def_native_method("send", tcp_socket_send)
  socket_class_global.def_native_method("recv", tcp_socket_recv)
  socket_class_global.def_native_method("recv_line", tcp_socket_recv_line)
  socket_class_global.def_native_method("close", tcp_socket_close)
  let socket_ref = new_ref(VkClass)
  socket_ref.class = socket_class_global
  result["TcpSocket".to_key()] = socket_ref.to_ref_value()

  server_class_global = new_class("TcpServer")
  server_class_global.def_native_method("accept", tcp_server_accept)
  server_class_global.def_native_method("close", tcp_server_close)
  let server_ref = new_ref(VkClass)
  server_ref.class = server_class_global
  result["TcpServer".to_key()] = server_ref.to_ref_value()

proc init_tcp_namespace*() =
  VmCreatedCallbacks.add proc() {.gcsafe.} =
    if App == NIL or App.kind != VkApplication:
      return
    if App.app.genex_ns.kind == VkNamespace:
      {.cast(gcsafe).}:
        App.app.genex_ns.ref.ns["tcp".to_key()] = build_tcp_namespace().to_value()

init_tcp_namespace()

proc init*(vm: ptr VirtualMachine): Namespace {.gcsafe.} =
  discard vm
  if App == NIL or App.kind != VkApplication:
    return nil
  if App.app.genex_ns.kind != VkNamespace:
    return nil
  let tcp_val = App.app.genex_ns.ref.ns.members.getOrDefault("tcp".to_key(), NIL)
  if tcp_val.kind == VkNamespace:
    return tcp_val.ref.ns
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
