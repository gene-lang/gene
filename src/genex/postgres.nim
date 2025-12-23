{.push warning[ResultShadowed]: off.}
import db_connector/db_postgres
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

# Convert Gene Value to PostgreSQL parameter string (with proper quoting)
proc gene_value_to_pg_string(value: Value): string =
  case value.kind
  of VkNil:
    result = "NULL"
  of VkBool:
    result = if value.to_bool: "true" else: "false"
  of VkInt:
    result = $value.int64
  of VkFloat:
    result = $value.float
  of VkString:
    # Escape single quotes by doubling them
    let escaped = value.str.replace("'", "''")
    result = "'" & escaped & "'"
  else:
    # Convert other types to string and quote
    let escaped = $value
    let escaped2 = escaped.replace("'", "''")
    result = "'" & escaped2 & "'"

# Convert seq[Value] to seq[string] for PostgreSQL
proc gene_values_to_pg_strings(params: seq[Value]): seq[string] =
  result = @[]
  for param in params:
    result.add(gene_value_to_pg_string(param))

# Substitute $1, $2, etc. placeholders in SQL with parameter values
proc substitute_params(sql_text: string, params: seq[string]): string =
  result = sql_text
  for i, param in params:
    let placeholder = "$" & intToStr(i + 1)
    result = result.replace(placeholder, param)

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
  let param_strings = gene_values_to_pg_strings(params)

  try:
    var result = new_array_value(@[])
    # Substitute parameters into SQL
    let final_sql = substitute_params(stmt_text, param_strings)
    for row in wrapper.conn.getAllRows(sql(final_sql)):
      var row_array = new_array_value(@[])
      for col in row:
        row_array.array_data.add(col.to_value())
      result.array_data.add(row_array)
    return result
  except DbError as e:
    raise new_exception(types.Exception, "SQL execution failed: " & e.msg)

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
  let param_strings = gene_values_to_pg_strings(params)

  try:
    # Substitute parameters into SQL and execute
    let final_sql = substitute_params(stmt_text, param_strings)
    wrapper.conn.exec(sql(final_sql))
  except DbError as e:
    raise new_exception(types.Exception, "SQL execution failed: " & e.msg)

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
