import unittest, os, strutils

import ../src/gene/vm
import ../src/gene/logging_core
import ../src/gene/types except Exception
import ./helpers

test "Logging defaults when config missing":
  reset_logging_config()
  load_logging_config(joinPath(getTempDir(), "missing_logging.gene"))
  check effective_level("any/logger") == LlInfo

test "Logging resolves longest prefix":
  let dir = joinPath(getTempDir(), "gene_logging_test")
  createDir(dir)
  let config_path = joinPath(dir, "logging.gene")
  writeFile(config_path, """
{^level "INFO"
 ^loggers {
  ^examples {^level "WARN"}
  ^examples/app.gene {^level "DEBUG"}
  ^examples/app.gene/Http {^level "TRACE"}
  ^examples/app.gene/Http/Todo {^level "ERROR"}
 }}
""")

  reset_logging_config()
  load_logging_config(config_path)
  check effective_level("examples/app.gene/Http/Todo") == LlError
  check effective_level("examples/app.gene/Http/Other") == LlTrace
  check effective_level("examples/app.gene/Other") == LlDebug
  check effective_level("examples/other.gene") == LlWarn
  check effective_level("other") == LlInfo

test "Logging format includes level and name":
  # Save and restore global state to avoid test pollution
  let saved_thread_id = current_thread_id
  try:
    current_thread_id = 0
    let line = format_log_line(LlInfo, "examples/app.gene", "hello")
    # Verify pattern: "T## INFO <timestamp> <logger_name> <message>"
    check line.startsWith("T00 INFO ")
    check line.contains(" examples/app.gene ")
    check line.endsWith(" hello")
  finally:
    current_thread_id = saved_thread_id

test "Gene Logger emits log line":
  init_all()
  reset_logging_config()
  load_logging_config(joinPath(getTempDir(), "missing_logging.gene"))
  # Save and restore global state to avoid test pollution
  let saved_thread_id = current_thread_id
  try:
    current_thread_id = 0
    last_log_line = ""
    discard VM.exec("""
    (class A
      (/logger = (new genex/logging/Logger self))
      (method m []
        (logger .info "hello")
      )
    )
    (var a (new A))
    (a .m)
    """, "test_code.gene")
    check last_log_line.contains(" INFO ")
    check last_log_line.contains("test_code.gene/A")
    check last_log_line.endsWith(" hello")
  finally:
    current_thread_id = saved_thread_id
