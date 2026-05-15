{.push warning[ResultShadowed]: off.}
import db_connector/db_mysql
import std/locks
import ./db
import ../gene/vm/extension_abi

when defined(noExtensions):
  include ../gene/extension/boilerplate
else:
  import ../gene/types

var connection_class_global: Class

type
  MySQLConnection* = ref object of DatabaseConnection
    conn*: DbConn
    lock*: Lock

var connection_table: Table[system.int64, MySQLConnection]
var next_conn_id: system.int64
var connection_lock: Lock
initLock(connection_lock)

proc value_to_mysql_param(value: Value): string =
  case value.kind
  of VkNil:
    ""
  of VkBool:
    if value.to_bool: "1" else: "0"
  of VkInt:
    $value.int64
  of VkFloat:
    $value.float
  of VkString:
    value.str
  else:
    $value

proc collect_mysql_params(args: ptr UncheckedArray[Value], arg_count: int,
                          has_keyword_args: bool, start_idx: int): seq[string] =
  result = @[]
  for value in collect_params(args, arg_count, has_keyword_args, start_idx):
    result.add(value_to_mysql_param(value))

proc connection_id(self: Value): system.int64 =
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "MySQL method must be called on a Connection instance")
  let key = "__conn_id__".to_key()
  if not instance_props(self).hasKey(key):
    raise new_exception(types.Exception, "Invalid MySQL Connection instance")
  instance_props(self)[key].to_int()

proc get_connection(self: Value): MySQLConnection =
  let conn_id = connection_id(self)
  {.cast(gcsafe).}:
    withLock(connection_lock):
      if not connection_table.hasKey(conn_id):
        raise new_exception(types.Exception, "Connection not found")
      result = connection_table[conn_id]

proc vm_open(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
             has_keyword_args: bool): Value {.gcsafe.} =
  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional < 4:
    raise new_exception(types.Exception, "mysql/open requires host, user, password, and database")

  let host_arg = get_positional_arg(args, 0, has_keyword_args)
  let user_arg = get_positional_arg(args, 1, has_keyword_args)
  let password_arg = get_positional_arg(args, 2, has_keyword_args)
  let database_arg = get_positional_arg(args, 3, has_keyword_args)

  if host_arg.kind != VkString or user_arg.kind != VkString or
     password_arg.kind != VkString or database_arg.kind != VkString:
    raise new_exception(types.Exception, "mysql/open arguments must be strings")

  var host = host_arg.str
  if has_keyword_args:
    let port_arg = get_keyword_arg(args, "port")
    if port_arg != NIL:
      if port_arg.kind != VkInt:
        raise new_exception(types.Exception, "mysql/open ^port must be an integer")
      host = host & ":" & $port_arg.to_int()

  var conn: DbConn
  try:
    conn = db_mysql.open(host, user_arg.str, password_arg.str, database_arg.str)
  except:
    raise new_exception(types.Exception, "Failed to open MySQL database: " & getCurrentExceptionMsg())

  let wrapper = MySQLConnection(conn: conn, closed: false)
  initLock(wrapper.lock)

  var conn_id: system.int64
  {.cast(gcsafe).}:
    withLock(connection_lock):
      conn_id = next_conn_id
      next_conn_id += 1
      connection_table[conn_id] = wrapper

  let conn_class = block:
    {.cast(gcsafe).}:
      (if connection_class_global != nil: connection_class_global else: new_class("Connection"))
  let instance = new_instance_value(conn_class)
  instance_props(instance)["__conn_id__".to_key()] = conn_id.to_value()
  instance

proc vm_query(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
              has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 2:
    raise new_exception(types.Exception, "mysql query requires self and SQL statement")

  let self = get_positional_arg(args, 0, has_keyword_args)
  let sql_arg = get_positional_arg(args, 1, has_keyword_args)
  if sql_arg.kind != VkString:
    raise new_exception(types.Exception, "SQL statement must be a string")

  let wrapper = get_connection(self)
  let params = collect_mysql_params(args, arg_count, has_keyword_args, 2)
  let stmt_text = sql_arg.str

  var result_rows = new_array_value(@[])
  {.cast(gcsafe).}:
    withLock(wrapper.lock):
      if wrapper.closed:
        raise new_exception(types.Exception, "Connection is closed")
      try:
        for row in wrapper.conn.instantRows(sql(stmt_text), params):
          var row_array = new_array_value(@[])
          for col in 0..<row.len.int:
            row_array.array_data.add(row[int32(col)].to_value())
          result_rows.array_data.add(row_array)
      except DbError as e:
        raise new_exception(types.Exception, "MySQL query failed: " & e.msg)
  result_rows

proc vm_exec(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
             has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 2:
    raise new_exception(types.Exception, "mysql exec requires self and SQL statement")

  let self = get_positional_arg(args, 0, has_keyword_args)
  let sql_arg = get_positional_arg(args, 1, has_keyword_args)
  if sql_arg.kind != VkString:
    raise new_exception(types.Exception, "SQL statement must be a string")

  let wrapper = get_connection(self)
  let params = collect_mysql_params(args, arg_count, has_keyword_args, 2)
  let stmt_text = sql_arg.str

  {.cast(gcsafe).}:
    withLock(wrapper.lock):
      if wrapper.closed:
        raise new_exception(types.Exception, "Connection is closed")
      try:
        wrapper.conn.exec(sql(stmt_text), params)
      except DbError as e:
        raise new_exception(types.Exception, "MySQL exec failed: " & e.msg)
  NIL

proc exec_transaction(self: Value, statement: string, context: string): Value =
  let wrapper = get_connection(self)
  {.cast(gcsafe).}:
    withLock(wrapper.lock):
      if wrapper.closed:
        raise new_exception(types.Exception, "Connection is closed")
      try:
        wrapper.conn.exec(sql(statement))
      except DbError as e:
        raise new_exception(types.Exception, "Failed to " & context & ": " & e.msg)
  NIL

proc vm_begin(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
              has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "begin requires self")
  exec_transaction(get_positional_arg(args, 0, has_keyword_args), "START TRANSACTION", "begin transaction")

proc vm_commit(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
               has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "commit requires self")
  exec_transaction(get_positional_arg(args, 0, has_keyword_args), "COMMIT", "commit transaction")

proc vm_rollback(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                 has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "rollback requires self")
  exec_transaction(get_positional_arg(args, 0, has_keyword_args), "ROLLBACK", "rollback transaction")

proc vm_close(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
              has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "close requires self")

  let self = get_positional_arg(args, 0, has_keyword_args)
  let wrapper = get_connection(self)

  {.cast(gcsafe).}:
    withLock(wrapper.lock):
      if not wrapper.closed:
        try:
          db_mysql.close(wrapper.conn)
          wrapper.closed = true
        except:
          raise new_exception(types.Exception, "Failed to close MySQL connection: " & getCurrentExceptionMsg())
  NIL

proc init_mysql_classes*() =
  connection_table = initTable[system.int64, MySQLConnection]()
  next_conn_id = 1

  VmCreatedCallbacks.add proc() =
    if App == NIL or App.kind != VkApplication:
      return

    {.cast(gcsafe).}:
      connection_class_global = new_class("Connection")
      connection_class_global.def_native_method("query", vm_query)
      connection_class_global.def_native_method("exec", vm_exec)
      connection_class_global.def_native_method("begin", vm_begin)
      connection_class_global.def_native_method("commit", vm_commit)
      connection_class_global.def_native_method("rollback", vm_rollback)
      connection_class_global.def_native_method("close", vm_close)

    let connection_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      connection_class_ref.class = connection_class_global

    if App.app.genex_ns.kind == VkNamespace:
      let mysql_ns = new_ref(VkNamespace)
      mysql_ns.ns = new_namespace("mysql")

      let open_fn = new_ref(VkNativeFn)
      open_fn.native_fn = vm_open
      mysql_ns.ns["open".to_key()] = open_fn.to_ref_value()
      mysql_ns.ns["Connection".to_key()] = connection_class_ref.to_ref_value()

      App.app.genex_ns.ref.ns["mysql".to_key()] = mysql_ns.to_ref_value()

init_mysql_classes()

proc init*(vm: ptr VirtualMachine): Namespace {.gcsafe.} =
  discard vm
  if App == NIL or App.kind != VkApplication:
    return nil
  if App.app.genex_ns.kind != VkNamespace:
    return nil
  let mysql_val = App.app.genex_ns.ref.ns.members.getOrDefault("mysql".to_key(), NIL)
  if mysql_val.kind == VkNamespace:
    return mysql_val.ref.ns
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
