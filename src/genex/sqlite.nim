import db_connector/db_sqlite
import db_connector/sqlite3 as sqlite3mod
import tables

# For static linking, don't include boilerplate to avoid duplicate set_globals
when defined(noExtensions):
  include ../gene/extension/boilerplate
else:
  # Statically linked - just import types directly
  import ../gene/types

# Global Connection class
var connection_class_global: Class
var statement_class_global: Class

# Custom wrapper for SQLite connection
type
  ConnectionWrapper* = ref object of RootObj
    conn*: DbConn
    closed*: bool

# Global table to store connections by ID
var connection_table {.threadvar.}: Table[system.int64, ConnectionWrapper]
var next_conn_id {.threadvar.}: system.int64

proc bind_gene_param(stmt: SqlPrepared, idx: int, value: Value) =
  case value.kind
  of VkNil:
    stmt.bindNull(idx)
  of VkBool:
    stmt.bindParam(idx, if value.to_bool: 1 else: 0)
  of VkInt:
    stmt.bindParam(idx, value.int64)
  of VkFloat:
    stmt.bindParam(idx, value.float)
  of VkString:
    stmt.bindParam(idx, value.str)
  else:
    stmt.bindParam(idx, $value)

proc bind_gene_params(stmt: SqlPrepared, params: seq[Value]) =
  for i, param in params:
    bind_gene_param(stmt, i + 1, param)

proc collect_params(args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool, start_idx: int): seq[Value] =
  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional <= start_idx:
    return @[]
  result = @[]
  for i in start_idx..<positional:
    result.add(get_positional_arg(args, i, has_keyword_args))

proc finalize_stmt(stmt: SqlPrepared) =
  discard sqlite3mod.finalize(stmt.PStmt)

# Open a database connection
proc vm_open(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 1:
    raise new_exception(types.Exception, "open requires a database path")

  let db_path_arg = get_positional_arg(args, 0, has_keyword_args)
  if db_path_arg.kind != VkString:
    raise new_exception(types.Exception, "database path must be a string")

  let db_path = db_path_arg.str

  # Open the database
  var conn: DbConn
  try:
    conn = open(db_path, "", "", "")
  except:
    raise new_exception(types.Exception, "Failed to open database: " & getCurrentExceptionMsg())

  # Create wrapper
  var wrapper = ConnectionWrapper(conn: conn, closed: false)

  # Store in global table
  let conn_id = next_conn_id
  next_conn_id += 1
  connection_table[conn_id] = wrapper

  # Create Connection instance
  let instance = new_ref(VkInstance)
  {.cast(gcsafe).}:
    if connection_class_global != nil:
      instance.instance_class = connection_class_global
    else:
      instance.instance_class = new_class("Connection")

  # Store the connection ID
  instance.instance_props["__conn_id__".to_key()] = conn_id.to_value()

  return instance.to_ref_value()

# Execute a SQL statement and return results
proc vm_exec(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 2:
    raise new_exception(types.Exception, "exec requires self and SQL statement")

  let self = get_positional_arg(args, 0, has_keyword_args)
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "exec must be called on a Connection instance")

  let conn_id_key = "__conn_id__".to_key()
  if not self.ref.instance_props.hasKey(conn_id_key):
    raise new_exception(types.Exception, "Invalid Connection instance")

  let conn_id = self.ref.instance_props[conn_id_key].to_int()
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

  let prepared = wrapper.conn.prepare(stmt_text)
  var result = new_array_value(@[])
  try:
    bind_gene_params(prepared, params)
    for row in wrapper.conn.instantRows(prepared):
      let column_count = row.len.int
      var row_array = new_array_value(@[])
      for col in 0..<column_count:
        row_array.ref.arr.add(row[int32(col)].to_value())
      result.ref.arr.add(row_array)
  except DbError as e:
    raise new_exception(types.Exception, "SQL execution failed: " & e.msg)
  finally:
    finalize_stmt(prepared)

  return result

# Execute a SQL statement without returning results (for INSERT, UPDATE, DELETE, etc.)
proc vm_execute(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 2:
    raise new_exception(types.Exception, "execute requires self and SQL statement")

  let self = get_positional_arg(args, 0, has_keyword_args)
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "execute must be called on a Connection instance")

  let conn_id_key = "__conn_id__".to_key()
  if not self.ref.instance_props.hasKey(conn_id_key):
    raise new_exception(types.Exception, "Invalid Connection instance")

  let conn_id = self.ref.instance_props[conn_id_key].to_int()
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

  let prepared = wrapper.conn.prepare(stmt_text)
  bind_gene_params(prepared, params)

  try:
    var rc = sqlite3mod.step(prepared.PStmt)
    while rc == sqlite3mod.SQLITE_ROW:
      rc = sqlite3mod.step(prepared.PStmt)
    if rc != sqlite3mod.SQLITE_DONE:
      let err = $sqlite3mod.errmsg(wrapper.conn)
      raise new_exception(types.Exception, "SQL execution failed: " & err)
  except DbError as e:
    raise new_exception(types.Exception, "SQL execution failed: " & e.msg)
  finally:
    finalize_stmt(prepared)

  return NIL

# Close the database connection
proc vm_close(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if arg_count < 1:
    raise new_exception(types.Exception, "close requires self")

  let self = get_positional_arg(args, 0, has_keyword_args)
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "close must be called on a Connection instance")

  # Get the wrapper
  let conn_id_key = "__conn_id__".to_key()
  if not self.ref.instance_props.hasKey(conn_id_key):
    raise new_exception(types.Exception, "Invalid Connection instance")

  let conn_id = self.ref.instance_props[conn_id_key].to_int()
  if not connection_table.hasKey(conn_id):
    raise new_exception(types.Exception, "Connection not found")

  let wrapper = connection_table[conn_id]

  if not wrapper.closed:
    try:
      db_sqlite.close(wrapper.conn)
      wrapper.closed = true
    except:
      raise new_exception(types.Exception, "Failed to close connection: " & getCurrentExceptionMsg())

  return NIL

# Initialize SQLite classes and functions
proc init_sqlite_classes*() =
  # Initialize connection table
  connection_table = initTable[system.int64, ConnectionWrapper]()
  next_conn_id = 1

  VmCreatedCallbacks.add proc() =
    # Ensure App is initialized
    if App == NIL or App.kind != VkApplication:
      return

    # Create Connection class
    {.cast(gcsafe).}:
      connection_class_global = new_class("Connection")
      connection_class_global.def_native_method("exec", vm_exec)
      connection_class_global.def_native_method("execute", vm_execute)
      connection_class_global.def_native_method("close", vm_close)

    # Create Statement class (placeholder for future implementation)
    {.cast(gcsafe).}:
      statement_class_global = new_class("Statement")

    # Store classes in gene namespace
    let connection_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      connection_class_ref.class = connection_class_global
    let statement_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      statement_class_ref.class = statement_class_global

    if App.app.genex_ns.kind == VkNamespace:
      # Create a sqlite namespace under genex
      let sqlite_ns = new_ref(VkNamespace)
      sqlite_ns.ns = new_namespace("sqlite")

      # Add open function
      let open_fn = new_ref(VkNativeFn)
      open_fn.native_fn = vm_open
      sqlite_ns.ns["open".to_key()] = open_fn.to_ref_value()

      # Add classes to sqlite namespace
      sqlite_ns.ns["Connection".to_key()] = connection_class_ref.to_ref_value()
      sqlite_ns.ns["Statement".to_key()] = statement_class_ref.to_ref_value()

      # Attach to genex namespace
      App.app.genex_ns.ref.ns["sqlite".to_key()] = sqlite_ns.to_ref_value()

# Call init function
init_sqlite_classes()
