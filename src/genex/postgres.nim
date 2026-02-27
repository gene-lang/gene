{.push warning[ResultShadowed]: off.}
import db_connector/db_postgres
import db_connector/postgres
import strutils
import ./db

# For static linking, don't include boilerplate to avoid duplicate set_globals
when defined(noExtensions):
  include ../gene/extension/boilerplate
else:
  # Statically linked - just import types directly
  import ../gene/types

# Global Connection class
var connection_class_global: Class

# Custom wrapper for PostgreSQL connection
type
  PostgresConnection* = ref object of DatabaseConnection
    conn*: DbConn

# Global table to store connections by ID
var connection_table {.threadvar.}: Table[system.int64, PostgresConnection]
var next_conn_id {.threadvar.}: system.int64

type
  PgParamBindings = object
    param_values: cstringArray
    owned_values: seq[string]
    param_count: int32

proc gene_value_to_pg_param_text(value: Value): string =
  case value.kind
  of VkBool:
    if value.to_bool: "true" else: "false"
  of VkInt:
    $value.int64
  of VkFloat:
    $value.float
  of VkString:
    value.str
  else:
    $value

proc free_pg_param_bindings(bindings: var PgParamBindings) =
  if bindings.param_values != nil:
    dealloc(bindings.param_values)
    bindings.param_values = nil
  bindings.owned_values.setLen(0)
  bindings.param_count = 0

proc build_pg_param_bindings(params: seq[Value]): PgParamBindings =
  result.param_count = params.len.int32
  if params.len == 0:
    return

  result.param_values = cast[cstringArray](alloc0(params.len * sizeof(cstring)))
  result.owned_values = @[]
  for i, param in params:
    if param.kind == VkNil:
      # NULL parameters are passed as nil C pointers.
      result.param_values[i] = nil
      continue
    let converted = gene_value_to_pg_param_text(param)
    result.owned_values.add(converted)
    result.param_values[i] = result.owned_values[^1].cstring

proc pg_error_message(conn: DbConn, res: PPGresult): string =
  if res != nil:
    let result_msg = pqresultErrorMessage(res)
    if result_msg != nil:
      let msg = ($result_msg).strip()
      if msg.len > 0:
        return msg
  let conn_msg = pqerrorMessage(conn)
  if conn_msg != nil:
    let msg = ($conn_msg).strip()
    if msg.len > 0:
      return msg
  "unknown PostgreSQL error"

# Open a PostgreSQL database connection
proc vm_open(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 1:
    raise new_exception(types.Exception, "open requires a connection string")

  let conn_str_arg = get_positional_arg(args, 0, has_keyword_args)
  if conn_str_arg.kind != VkString:
    raise new_exception(types.Exception, "connection string must be a string")

  let conn_str = conn_str_arg.str

  # Open the database
  var conn: DbConn
  try:
    conn = db_postgres.open("", "", "", conn_str)
  except:
    raise new_exception(types.Exception, "Failed to open database: " & getCurrentExceptionMsg())

  # Create wrapper
  var wrapper = PostgresConnection(conn: conn, closed: false)

  # Store in global table
  let conn_id = next_conn_id
  next_conn_id += 1
  connection_table[conn_id] = wrapper

  # Create Connection instance
  let conn_class = block:
    {.cast(gcsafe).}:
      (if connection_class_global != nil: connection_class_global else: new_class("Connection"))
  let instance = new_instance_value(conn_class)

  # Store the connection ID
  instance_props(instance)["__conn_id__".to_key()] = conn_id.to_value()

  return instance

# Execute a SQL query and return results (SELECT)
proc vm_query(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 2:
    raise new_exception(types.Exception, "query requires self and SQL statement")

  let self = get_positional_arg(args, 0, has_keyword_args)
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "query must be called on a Connection instance")

  let conn_id_key = "__conn_id__".to_key()
  if not instance_props(self).hasKey(conn_id_key):
    raise new_exception(types.Exception, "Invalid Connection instance")

  let conn_id = instance_props(self)[conn_id_key].to_int()
  if not connection_table.hasKey(conn_id):
    raise new_exception(types.Exception, "Connection not found")

  let wrapper = connection_table[conn_id]
  if wrapper.closed:
    raise new_exception(types.Exception, "Connection is closed")

  let sql_arg = get_positional_arg(args, 1, has_keyword_args)
  if sql_arg.kind != VkString:
    raise new_exception(types.Exception, "SQL statement must be a string")

  let stmt_text = sql_arg.str
  let params = collect_params(args, arg_count, has_keyword_args, 2)
  var bindings = build_pg_param_bindings(params)
  var raw_result: PPGresult = nil
  try:
    raw_result = pqexecParams(
      wrapper.conn,
      stmt_text.cstring,
      bindings.param_count,
      nil,
      bindings.param_values,
      nil,
      nil,
      0
    )

    if raw_result == nil or pqresultStatus(raw_result) != PGRES_TUPLES_OK:
      raise new_exception(types.Exception, "SQL execution failed: " & pg_error_message(wrapper.conn, raw_result))

    var result = new_array_value(@[])
    let row_count = pqntuples(raw_result)
    let col_count = pqnfields(raw_result)
    for row_idx in 0..<row_count:
      var row_array = new_array_value(@[])
      for col_idx in 0..<col_count:
        if pqgetisnull(raw_result, row_idx, col_idx) == 1:
          # Keep compatibility with existing PostgreSQL bridge behavior.
          row_array.array_data.add("".to_value())
        else:
          row_array.array_data.add(($pqgetvalue(raw_result, row_idx, col_idx)).to_value())
      result.array_data.add(row_array)
    return result
  finally:
    if raw_result != nil:
      pqclear(raw_result)
    free_pg_param_bindings(bindings)

# Execute a SQL statement without returning results (INSERT, UPDATE, DELETE)
proc vm_exec(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 2:
    raise new_exception(types.Exception, "exec requires self and SQL statement")

  let self = get_positional_arg(args, 0, has_keyword_args)
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "exec must be called on a Connection instance")

  let conn_id_key = "__conn_id__".to_key()
  if not instance_props(self).hasKey(conn_id_key):
    raise new_exception(types.Exception, "Invalid Connection instance")

  let conn_id = instance_props(self)[conn_id_key].to_int()
  if not connection_table.hasKey(conn_id):
    raise new_exception(types.Exception, "Connection not found")

  let wrapper = connection_table[conn_id]
  if wrapper.closed:
    raise new_exception(types.Exception, "Connection is closed")

  let sql_arg = get_positional_arg(args, 1, has_keyword_args)
  if sql_arg.kind != VkString:
    raise new_exception(types.Exception, "SQL statement must be a string")

  let stmt_text = sql_arg.str
  let params = collect_params(args, arg_count, has_keyword_args, 2)
  var bindings = build_pg_param_bindings(params)
  var raw_result: PPGresult = nil
  try:
    raw_result = pqexecParams(
      wrapper.conn,
      stmt_text.cstring,
      bindings.param_count,
      nil,
      bindings.param_values,
      nil,
      nil,
      0
    )

    if raw_result == nil or pqresultStatus(raw_result) != PGRES_COMMAND_OK:
      raise new_exception(types.Exception, "SQL execution failed: " & pg_error_message(wrapper.conn, raw_result))
  finally:
    if raw_result != nil:
      pqclear(raw_result)
    free_pg_param_bindings(bindings)

  return NIL

# Begin a transaction
proc vm_begin(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 1:
    raise new_exception(types.Exception, "begin requires self")

  let self = get_positional_arg(args, 0, has_keyword_args)
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "begin must be called on a Connection instance")

  let conn_id_key = "__conn_id__".to_key()
  if not instance_props(self).hasKey(conn_id_key):
    raise new_exception(types.Exception, "Invalid Connection instance")

  let conn_id = instance_props(self)[conn_id_key].to_int()
  if not connection_table.hasKey(conn_id):
    raise new_exception(types.Exception, "Connection not found")

  let wrapper = connection_table[conn_id]
  if wrapper.closed:
    raise new_exception(types.Exception, "Connection is closed")

  try:
    wrapper.conn.exec(sql"BEGIN")
  except DbError as e:
    raise new_exception(types.Exception, "Failed to begin transaction: " & e.msg)

  return NIL

# Commit a transaction
proc vm_commit(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 1:
    raise new_exception(types.Exception, "commit requires self")

  let self = get_positional_arg(args, 0, has_keyword_args)
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "commit must be called on a Connection instance")

  let conn_id_key = "__conn_id__".to_key()
  if not instance_props(self).hasKey(conn_id_key):
    raise new_exception(types.Exception, "Invalid Connection instance")

  let conn_id = instance_props(self)[conn_id_key].to_int()
  if not connection_table.hasKey(conn_id):
    raise new_exception(types.Exception, "Connection not found")

  let wrapper = connection_table[conn_id]
  if wrapper.closed:
    raise new_exception(types.Exception, "Connection is closed")

  try:
    wrapper.conn.exec(sql"COMMIT")
  except DbError as e:
    raise new_exception(types.Exception, "Failed to commit transaction: " & e.msg)

  return NIL

# Rollback a transaction
proc vm_rollback(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 1:
    raise new_exception(types.Exception, "rollback requires self")

  let self = get_positional_arg(args, 0, has_keyword_args)
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "rollback must be called on a Connection instance")

  let conn_id_key = "__conn_id__".to_key()
  if not instance_props(self).hasKey(conn_id_key):
    raise new_exception(types.Exception, "Invalid Connection instance")

  let conn_id = instance_props(self)[conn_id_key].to_int()
  if not connection_table.hasKey(conn_id):
    raise new_exception(types.Exception, "Connection not found")

  let wrapper = connection_table[conn_id]
  if wrapper.closed:
    raise new_exception(types.Exception, "Connection is closed")

  try:
    wrapper.conn.exec(sql"ROLLBACK")
  except DbError as e:
    raise new_exception(types.Exception, "Failed to rollback transaction: " & e.msg)

  return NIL

# Close the database connection
proc vm_close(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 1:
    raise new_exception(types.Exception, "close requires self")

  let self = get_positional_arg(args, 0, has_keyword_args)
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "close must be called on a Connection instance")

  # Get the wrapper
  let conn_id_key = "__conn_id__".to_key()
  if not instance_props(self).hasKey(conn_id_key):
    raise new_exception(types.Exception, "Invalid Connection instance")

  let conn_id = instance_props(self)[conn_id_key].to_int()
  if not connection_table.hasKey(conn_id):
    raise new_exception(types.Exception, "Connection not found")

  let wrapper = connection_table[conn_id]

  if not wrapper.closed:
    try:
      db_postgres.close(wrapper.conn)
      wrapper.closed = true
    except:
      raise new_exception(types.Exception, "Failed to close connection: " & getCurrentExceptionMsg())

  return NIL

# Initialize PostgreSQL classes and functions
proc init_postgres_classes*() =
  # Initialize connection table
  connection_table = initTable[system.int64, PostgresConnection]()
  next_conn_id = 1

  VmCreatedCallbacks.add proc() =
    # Ensure App is initialized
    if App == NIL or App.kind != VkApplication:
      return

    # Create Connection class
    {.cast(gcsafe).}:
      connection_class_global = new_class("Connection")
      connection_class_global.def_native_method("query", vm_query)
      connection_class_global.def_native_method("exec", vm_exec)
      connection_class_global.def_native_method("begin", vm_begin)
      connection_class_global.def_native_method("commit", vm_commit)
      connection_class_global.def_native_method("rollback", vm_rollback)
      connection_class_global.def_native_method("close", vm_close)

    # Store class in gene namespace
    let connection_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      connection_class_ref.class = connection_class_global

    if App.app.genex_ns.kind == VkNamespace:
      # Create a postgres namespace under genex
      let postgres_ns = new_ref(VkNamespace)
      postgres_ns.ns = new_namespace("postgres")

      # Add open function
      let open_fn = new_ref(VkNativeFn)
      open_fn.native_fn = vm_open
      postgres_ns.ns["open".to_key()] = open_fn.to_ref_value()

      # Add Connection class to postgres namespace
      postgres_ns.ns["Connection".to_key()] = connection_class_ref.to_ref_value()

      # Attach to genex namespace
      App.app.genex_ns.ref.ns["postgres".to_key()] = postgres_ns.to_ref_value()

# Call init function
init_postgres_classes()

{.pop.}
