import os, osproc, std/cmdline, strutils

import ./model

type
  EditorCommand* = object
    command*: string
    args*: seq[string]

proc parse_editor_command*(raw: string): EditorCommand =
  let parts = parseCmdLine(raw)
  if parts.len == 0:
    raise newException(ViewerError, "Editor command is empty")
  result.command = parts[0]
  if parts.len > 1:
    result.args = parts[1 .. ^1]
  else:
    result.args = @[]

proc editor_name(command: string): string =
  splitFile(command).name.toLowerAscii()

proc editor_launch_args*(editor: EditorCommand, file_path: string, line, column: int): seq[string] =
  result = editor.args
  let safe_line = max(1, line)
  let safe_column = max(1, column)
  if editor_name(editor.command) in ["nvim", "vim", "vi"]:
    result.add("+call cursor(" & $safe_line & "," & $safe_column & ")")
  result.add(file_path)

proc resolve_editor_command*(): EditorCommand =
  let configured = getEnv("EDITOR").strip()
  if configured.len > 0:
    return parse_editor_command(configured)

  for candidate in ["nvim", "vim", "vi"]:
    if findExe(candidate).len > 0:
      return EditorCommand(command: candidate, args: @[])

  raise newException(ViewerError, "No editor found. Set $EDITOR or install nvim.")

proc launch_external_editor*(file_path: string, line, column: int): int =
  let editor = resolve_editor_command()
  let process = startProcess(
    editor.command,
    args = editor_launch_args(editor, file_path, line, column),
    options = {poUsePath, poParentStreams}
  )
  defer:
    close(process)
  waitForExit(process)
