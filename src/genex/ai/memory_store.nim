## SQLite-backed memory service for conversation persistence.
## Provides append/recent/retrieve/summarize with durable storage.
## Replaces the in-memory ConversationStore for production use.

import std/json
import std/strutils
import db_connector/db_sqlite

import ./utils
import ./conversation


type
  MemoryStore* = ref object
    db*: DbConn
    path*: string


proc now_ms(): int64 {.inline.} =
  now_unix_ms()


proc init_schema(db: DbConn) =
  db.exec(sql"""CREATE TABLE IF NOT EXISTS memory_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    meta_json TEXT DEFAULT '{}',
    created_at_ms INTEGER NOT NULL
  )""")

  db.exec(sql"""CREATE INDEX IF NOT EXISTS idx_memory_events_session
    ON memory_events(session_id, created_at_ms)""")

  db.exec(sql"""CREATE INDEX IF NOT EXISTS idx_memory_events_workspace
    ON memory_events(workspace_id, session_id)""")

  db.exec(sql"""CREATE TABLE IF NOT EXISTS memory_summaries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    summary TEXT NOT NULL,
    window_start_ms INTEGER NOT NULL,
    window_end_ms INTEGER NOT NULL,
    created_at_ms INTEGER NOT NULL
  )""")

  db.exec(sql"""CREATE INDEX IF NOT EXISTS idx_memory_summaries_session
    ON memory_summaries(session_id, created_at_ms)""")


proc new_memory_store*(path: string): MemoryStore =
  let db = open(path, "", "", "")
  init_schema(db)
  MemoryStore(db: db, path: path)

proc close*(store: MemoryStore) =
  if not store.isNil:
    store.db.close()


# --- append ---

proc append_event*(store: MemoryStore; workspace_id: string; session_id: string;
                   role: string; content: string; metadata: JsonNode = nil) =
  if store.isNil:
    raise newException(ValueError, "MemoryStore is nil")
  if session_id.len == 0:
    raise newException(ValueError, "session_id cannot be empty")

  let meta_str =
    if metadata.isNil or metadata.kind == JNull: "{}"
    else: $metadata
  let ts = now_ms()

  store.db.exec(sql"""INSERT INTO memory_events
    (workspace_id, session_id, role, content, meta_json, created_at_ms)
    VALUES (?, ?, ?, ?, ?, ?)""",
    workspace_id, session_id, role, content, meta_str, ts)


# --- recent ---

proc get_recent*(store: MemoryStore; session_id: string; limit = 20): seq[ConversationEvent] =
  if store.isNil or session_id.len == 0:
    return @[]

  let rows = store.db.getAllRows(sql"""
    SELECT role, content, meta_json, created_at_ms
    FROM memory_events
    WHERE session_id = ?
    ORDER BY created_at_ms DESC, id DESC
    LIMIT ?""",
    session_id, limit)

  # Reverse so oldest is first
  for i in countdown(rows.len - 1, 0):
    let row = rows[i]
    let meta =
      try: parseJson(row[2])
      except: newJObject()
    result.add(ConversationEvent(
      role: row[0],
      content: row[1],
      metadata: meta,
      created_at_ms:
        try: parseInt(row[3]).int64
        except: 0'i64
    ))


# --- retrieve by scope ---

proc retrieve*(store: MemoryStore; workspace_id: string; session_id = "";
               query = ""; limit = 20): seq[ConversationEvent] =
  ## Retrieve events scoped to a workspace. Optionally filter by session_id
  ## and/or substring query in content.
  if store.isNil or workspace_id.len == 0:
    return @[]

  var sql_str = "SELECT role, content, meta_json, created_at_ms FROM memory_events WHERE workspace_id = ?"
  var params: seq[string] = @[workspace_id]

  if session_id.len > 0:
    sql_str &= " AND session_id = ?"
    params.add(session_id)

  if query.len > 0:
    sql_str &= " AND content LIKE ?"
    params.add("%" & query & "%")

  sql_str &= " ORDER BY created_at_ms DESC, id DESC LIMIT ?"
  params.add($limit)

  let rows = store.db.getAllRows(sql(sql_str), params)

  # Reverse so oldest is first
  for i in countdown(rows.len - 1, 0):
    let row = rows[i]
    let meta =
      try: parseJson(row[2])
      except: newJObject()
    result.add(ConversationEvent(
      role: row[0],
      content: row[1],
      metadata: meta,
      created_at_ms:
        try: parseInt(row[3]).int64
        except: 0'i64
    ))


# --- prune ---

proc prune_session*(store: MemoryStore; session_id: string; keep_last: int) =
  ## Remove all but the most recent `keep_last` events in a session.
  if store.isNil or session_id.len == 0:
    return

  if keep_last <= 0:
    store.db.exec(sql"DELETE FROM memory_events WHERE session_id = ?", session_id)
    return

  # Delete everything except the newest keep_last rows
  store.db.exec(sql"""DELETE FROM memory_events
    WHERE session_id = ? AND id NOT IN (
      SELECT id FROM memory_events
      WHERE session_id = ?
      ORDER BY created_at_ms DESC, id DESC
      LIMIT ?
    )""",
    session_id, session_id, keep_last)


# --- summarize ---

proc summarize_recent*(store: MemoryStore; session_id: string; limit = 12): string =
  let recent = store.get_recent(session_id, limit)
  if recent.len == 0:
    return ""

  var lines: seq[string] = @[]
  for item in recent:
    lines.add(item.role.toLowerAscii() & ": " & item.content)
  lines.join("\n")


# --- summary checkpoints ---

proc save_summary*(store: MemoryStore; session_id: string; summary: string;
                   window_start_ms: int64; window_end_ms: int64) =
  if store.isNil or session_id.len == 0 or summary.len == 0:
    return

  let ts = now_ms()
  store.db.exec(sql"""INSERT INTO memory_summaries
    (session_id, summary, window_start_ms, window_end_ms, created_at_ms)
    VALUES (?, ?, ?, ?, ?)""",
    session_id, summary, window_start_ms, window_end_ms, ts)

proc get_summaries*(store: MemoryStore; session_id: string; limit = 5): seq[JsonNode] =
  if store.isNil or session_id.len == 0:
    return @[]

  let rows = store.db.getAllRows(sql"""
    SELECT summary, window_start_ms, window_end_ms, created_at_ms
    FROM memory_summaries
    WHERE session_id = ?
    ORDER BY created_at_ms DESC
    LIMIT ?""",
    session_id, limit)

  for row in rows:
    result.add(%*{
      "summary": row[0],
      "window_start_ms": (try: parseInt(row[1]).int64 except: 0'i64),
      "window_end_ms": (try: parseInt(row[2]).int64 except: 0'i64),
      "created_at_ms": (try: parseInt(row[3]).int64 except: 0'i64)
    })


# --- event count ---

proc event_count*(store: MemoryStore; session_id: string): int =
  if store.isNil or session_id.len == 0:
    return 0
  let row = store.db.getRow(sql"SELECT COUNT(*) FROM memory_events WHERE session_id = ?", session_id)
  try: parseInt(row[0]) except: 0
