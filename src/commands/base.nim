import tables, logging

type
  CommandResult* = object
    success*: bool
    output*: string
    error*: string

  CommandManager* = ref object
    data*: Table[string, Command]
    help*: string

  Command* = proc(cmd: string, args: seq[string]): CommandResult

proc setup_logger*(debugging: bool) =
  var console_logger = new_console_logger()
  add_handler(console_logger)
  console_logger.level_threshold = Level.lvlInfo
  if debugging:
    console_logger.level_threshold = Level.lvlDebug

proc success*(output: string = ""): CommandResult =
  ## Creates a successful command result with optional output
  CommandResult(success: true, output: output, error: "")

proc failure*(error: string): CommandResult =
  ## Creates a failed command result with an error message
  CommandResult(success: false, output: "", error: error)

proc lookup*(self: CommandManager, cmd: string): Command =
  ## Safely looks up a command handler by name.
  ## Returns nil if the command is not found.
  if self.data.hasKey(cmd):
    return self.data[cmd]
  else:
    return nil

proc `[]`*(self: CommandManager, cmd: string): Command {.deprecated: "Use lookup() instead".} =
  ## Deprecated: Use lookup() for safe command retrieval
  if self.data.hasKey(cmd):
    return self.data[cmd]

proc register*(self: CommandManager, c: string, cmd: Command) =
  ## Registers a single command handler
  self.data[c] = cmd

proc register*(self: CommandManager, cmds: seq[string], cmd: Command) =
  ## Registers multiple command aliases for the same handler
  for c in cmds:
    self.data[c] = cmd

proc add_help*(self: CommandManager, help: string) =
  ## Adds help text to the command manager
  self.help &= help & "\n"
