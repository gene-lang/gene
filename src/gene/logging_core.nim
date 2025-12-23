import os, times, strutils, strformat, tables, locks

import ./types
import ./parser

type LogLevel* = enum
  LlError
  LlWarn
  LlInfo
  LlDebug
  LlTrace

const DefaultRootLevel = LlInfo

var logging_loaded* = false
var root_level* = DefaultRootLevel
var logger_levels* = initTable[string, LogLevel]()
var last_log_line* = ""

var log_lock: Lock
initLock(log_lock)

proc reset_logging_config*() =
  root_level = DefaultRootLevel
  logger_levels = initTable[string, LogLevel]()
  logging_loaded = false
  last_log_line = ""

proc level_rank(level: LogLevel): int =
  case level
  of LlError: 0
  of LlWarn: 1
  of LlInfo: 2
  of LlDebug: 3
  of LlTrace: 4

proc level_to_string*(level: LogLevel): string =
  case level
  of LlError: "ERROR"
  of LlWarn: "WARN"
  of LlInfo: "INFO"
  of LlDebug: "DEBUG"
  of LlTrace: "TRACE"

proc parse_log_level(name: string, out_level: var LogLevel): bool =
  case name.toUpperAscii()
  of "ERROR":
    out_level = LlError
    true
  of "WARN", "WARNING":
    out_level = LlWarn
    true
  of "INFO":
    out_level = LlInfo
    true
  of "DEBUG":
    out_level = LlDebug
    true
  of "TRACE":
    out_level = LlTrace
    true
  else:
    false

proc log_level_from_value(val: Value, fallback: LogLevel): LogLevel =
  case val.kind
  of VkString, VkSymbol:
    var parsed: LogLevel
    if parse_log_level(val.str, parsed):
      return parsed
  else:
    discard
  fallback

proc key_to_string(key: Key): string =
  let symbol_value = cast[Value](key)
  let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
  get_symbol(symbol_index.int)

proc load_logging_config*(config_path: string = "") =
  let path =
    if config_path.len > 0:
      config_path
    else:
      joinPath(getCurrentDir(), "config", "logging.gene")

  root_level = DefaultRootLevel
  logger_levels = initTable[string, LogLevel]()
  logging_loaded = true

  if not fileExists(path):
    return

  let content = readFile(path)
  var nodes: seq[Value]
  try:
    nodes = read_all(content)
  except CatchableError:
    return
  if nodes.len == 0:
    return
  let config_val = nodes[0]
  if config_val.kind != VkMap:
    return

  let config_map = map_data(config_val)
  root_level = log_level_from_value(config_map.getOrDefault("level".to_key(), NIL), root_level)

  let loggers_val = config_map.getOrDefault("loggers".to_key(), NIL)
  if loggers_val.kind != VkMap:
    return

  for key, entry in map_data(loggers_val):
    let logger_name = key_to_string(key)
    var level = root_level
    case entry.kind
    of VkMap:
      let entry_level = map_data(entry).getOrDefault("level".to_key(), NIL)
      level = log_level_from_value(entry_level, root_level)
    of VkString, VkSymbol:
      level = log_level_from_value(entry, root_level)
    else:
      discard
    logger_levels[logger_name] = level

proc ensure_logging_loaded() =
  if not logging_loaded:
    load_logging_config()

proc effective_level*(logger_name: string): LogLevel =
  ensure_logging_loaded()
  if logger_name.len == 0:
    return root_level

  var name = logger_name
  while true:
    if logger_levels.hasKey(name):
      return logger_levels[name]
    let idx = name.rfind("/")
    if idx < 0:
      break
    name = name[0..<idx]

  root_level

proc log_enabled*(level: LogLevel, logger_name: string): bool =
  let effective = effective_level(logger_name)
  level_rank(level) <= level_rank(effective)

proc format_log_line*(level: LogLevel, logger_name: string, message: string, timestamp: DateTime): string {.gcsafe.} =
  let thread_label = fmt"T{current_thread_id:02d}"
  let level_label = level_to_string(level)
  let time_format = init_time_format("yy-MM-dd ddd HH:mm:ss'.'fff")
  let time_label = timestamp.format(time_format)
  let name = if logger_name.len > 0: logger_name else: "unknown"
  result = thread_label & " " & level_label & " " & time_label & " " & name
  if message.len > 0:
    result &= " " & message

proc format_log_line*(level: LogLevel, logger_name: string, message: string): string {.gcsafe.} =
  format_log_line(level, logger_name, message, now())

proc log_message*(level: LogLevel, logger_name: string, message: string) {.gcsafe.} =
  var should_log = false
  {.cast(gcsafe).}:
    should_log = log_enabled(level, logger_name)
  if not should_log:
    return

  let line = format_log_line(level, logger_name, message)
  acquire(log_lock)
  try:
    {.cast(gcsafe).}:
      last_log_line = line
    echo line
  finally:
    release(log_lock)
