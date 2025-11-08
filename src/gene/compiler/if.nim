import tables

import ../types

const COND_KEY* = "cond"
const THEN_KEY* = "then"
const ELIF_KEY* = "elif"
const ELSE_KEY* = "else"
const INDEX_KEY* = "index"
const TOTAL_KEY* = "total"

type
  IfState = enum
    IsIf, IsIfCond, IsIfLogic,
    IsElif, IsElifCond, IsElifLogic,
    IsIfNot, IsElifNot,
    IsElse,

proc normalize_if*(self: ptr Gene) =
  # TODO: return a tuple to be used by the translator
  if self.props.has_key("cond".to_key()):
    return
  let `type` = self.type
  if `type` == "if".to_symbol_value():
    # Store if/elif/else block
    var logic: seq[Value]
    var elifs: seq[Value]

    var state = IsIf
    proc handler(input: Value) =
      case state:
      of IsIf:
        if input == nil:
          not_allowed()
        elif input == "not".to_symbol_value():
          state = IsIfNot
        else:
          self.props["cond".to_key()] = input
          state = IsIfCond
      of IsIfNot:
        let g = new_gene("not".to_symbol_value())
        g.children.add(input)
        self.props["cond".to_key()] = g.to_gene_value()
        state = IsIfCond
      of IsIfCond:
        state = IsIfLogic
        logic = @[]
        if input == nil:
          not_allowed()
        elif input == "else".to_symbol_value():
          state = IsElse
          logic = @[]
        elif input != "then".to_symbol_value():
          logic.add(input)
      of IsIfLogic:
        if input == nil:
          self.props["then".to_key()] = new_stream_value(logic)
        elif input == "elif".to_symbol_value():
          self.props["then".to_key()] = new_stream_value(logic)
          state = IsElif
        elif input == "else".to_symbol_value():
          self.props["then".to_key()] = new_stream_value(logic)
          state = IsElse
          logic = @[]
        else:
          logic.add(input)
      of IsElif:
        if input == nil:
          not_allowed()
        elif input == "not".to_symbol_value():
          state = IsElifNot
        else:
          elifs.add(input)
          state = IsElifCond
      of IsElifNot:
        let g = new_gene("not".to_symbol_value())
        g.children.add(input)
        elifs.add(g.to_gene_value())
        state = IsElifCond
      of IsElifCond:
        state = IsElifLogic
        logic = @[]
        if input == nil:
          not_allowed()
        elif input != "then".to_symbol_value():
          logic.add(input)
      of IsElifLogic:
        if input == nil:
          elifs.add(new_stream_value(logic))
          self.props["elif".to_key()] = new_array_value(elifs)
        elif input == "elif".to_symbol_value():
          elifs.add(new_stream_value(logic))
          self.props["elif".to_key()] = new_array_value(elifs)
          state = IsElif
        elif input == "else".to_symbol_value():
          elifs.add(new_stream_value(logic))
          self.props["elif".to_key()] = new_array_value(elifs)
          state = IsElse
          logic = @[]
        else:
          logic.add(input)
      of IsElse:
        if input == nil:
          self.props["else".to_key()] = new_stream_value(logic)
        else:
          logic.add(input)

    for item in self.children:
      handler(item)
    handler(nil)

    # Add empty blocks when they are missing
    if not self.props.has_key("then".to_key()):
      self.props["then".to_key()] = new_stream_value()
    if not self.props.has_key("else".to_key()):
      self.props["else".to_key()] = new_stream_value()

    if self.props["then".to_key()].ref.stream.len == 0:
      self.props["then".to_key()].ref.stream.add(NIL)
    if self.props["else".to_key()].ref.stream.len == 0:
      self.props["else".to_key()].ref.stream.add(NIL)

    self.children.reset  # Clear our gene_children as it's not needed any more
