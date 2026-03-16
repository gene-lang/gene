import terminal
import std/exitprocs

when not defined(windows):
  {.passL: "-lncurses".}

type
  CWindow {.importc: "WINDOW", header: "<curses.h>", incompleteStruct.} = object
  WindowPtr = ptr CWindow

  ViewerKey* = enum
    VkNone
    VkUp
    VkDown
    VkLeft
    VkRight
    VkF1
    VkF5
    VkF10
    VkResize
    VkQuit
    VkHelp

const
  NcKeyDown = 258
  NcKeyUp = 259
  NcKeyLeft = 260
  NcKeyRight = 261
  NcKeyF0 = 264
  NcKeyResize = 410
  NcAttrReverse = 0x0004_0000'u32

proc initscr(): WindowPtr {.importc, header: "<curses.h>".}
proc endwin(): cint {.importc, header: "<curses.h>".}
proc raw_mode(): cint {.importc: "raw", header: "<curses.h>".}
proc noecho(): cint {.importc, header: "<curses.h>".}
proc keypad(win: WindowPtr, enabled: cint): cint {.importc, header: "<curses.h>".}
proc curs_set(visibility: cint): cint {.importc, header: "<curses.h>".}
proc erase(): cint {.importc, header: "<curses.h>".}
proc refresh(): cint {.importc, header: "<curses.h>".}
proc getch(): cint {.importc, header: "<curses.h>".}
proc mvaddnstr(y, x: cint, text: cstring, n: cint): cint {.importc, header: "<curses.h>".}
proc attron(attrs: uint32): cint {.importc, header: "<curses.h>".}
proc attroff(attrs: uint32): cint {.importc, header: "<curses.h>".}

var stdscr {.importc, header: "<curses.h>".}: WindowPtr
var session_active = false
var hook_installed = false
var quit_proc_installed = false

type
  CursesSession* = object
    active*: bool

proc cleanup_terminal() {.noconv.} =
  if not session_active:
    return
  discard endwin()
  session_active = false

proc handle_ctrl_c() {.noconv.} =
  cleanup_terminal()
  quit(130)

proc terminal_height*(): int =
  terminalSize().h

proc terminal_width*(): int =
  terminalSize().w

proc open_session*(): CursesSession =
  if not quit_proc_installed:
    addExitProc(cleanup_terminal)
    quit_proc_installed = true
  if not hook_installed:
    setControlCHook(handle_ctrl_c)
    hook_installed = true
  discard initscr()
  discard raw_mode()
  discard noecho()
  discard keypad(stdscr, 1)
  discard curs_set(0)
  session_active = true
  CursesSession(active: true)

proc close_session*(session: var CursesSession) =
  if not session.active:
    return
  cleanup_terminal()
  when declared(unsetControlCHook):
    if hook_installed:
      unsetControlCHook()
      hook_installed = false
  session.active = false

proc clear_screen*() =
  discard erase()

proc present*() =
  discard refresh()

proc crop_line(text: string, width: int): string =
  if width <= 0:
    return ""
  if text.len <= width:
    return text
  if width <= 3:
    return text[0 ..< width]
  text[0 ..< width - 3] & "..."

proc draw_text*(row, col, width: int, text: string, highlighted = false) =
  let line = crop_line(text, width)
  if highlighted:
    discard attron(NcAttrReverse)
  discard mvaddnstr(row.cint, col.cint, line.cstring, line.len.cint)
  if highlighted:
    discard attroff(NcAttrReverse)

proc read_key*(): ViewerKey =
  let key = getch().int
  case key
  of NcKeyUp:
    VkUp
  of NcKeyDown:
    VkDown
  of NcKeyLeft:
    VkLeft
  of NcKeyRight:
    VkRight
  of NcKeyResize:
    VkResize
  of NcKeyF0 + 1:
    VkF1
  of NcKeyF0 + 5:
    VkF5
  of NcKeyF0 + 10:
    VkF10
  of int('q'), int('Q'):
    VkQuit
  of 3:
    VkQuit
  of int('?'):
    VkHelp
  else:
    VkNone
