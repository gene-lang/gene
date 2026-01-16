import tables

import ../types

const CASE_TARGET_KEY* = "case_target"
const CASE_WHEN_KEY* = "case_when"
const CASE_ELSE_KEY* = "case_else"

type
  CaseState = enum
    CsCase,           # Expecting target
    CsAfterTarget,    # After target, expecting 'when' or 'else'
    CsWhen,           # After 'when', expecting value
    CsWhenValue,      # After when value, expecting body or next when/else
    CsWhenBody,       # In when body
    CsElse,           # In else body

proc normalize_case*(self: ptr Gene) =
  ## Normalize case expression into structured props:
  ## - case_target: the value being matched
  ## - when: array of [value, body_stream] pairs
  ## - else: stream for else body
  
  if self.props.has_key(CASE_TARGET_KEY.to_key()):
    return  # Already normalized
  
  let `type` = self.type
  if `type` != "case".to_symbol_value():
    return
  
  var whens: seq[Value] = @[]
  var current_body: seq[Value] = @[]
  var else_body: seq[Value] = @[]
  
  var state = CsCase
  
  proc handler(input: Value) =
    case state:
    of CsCase:
      if input == nil:
        not_allowed("case: missing target expression")
      else:
        self.props[CASE_TARGET_KEY.to_key()] = input
        state = CsAfterTarget
    
    of CsAfterTarget:
      if input == nil:
        # No when clauses - just else
        discard
      elif input == "when".to_symbol_value():
        state = CsWhen
      elif input == "else".to_symbol_value():
        state = CsElse
      else:
        not_allowed("case: expected 'when' or 'else', got: " & $input)
    
    of CsWhen:
      if input == nil:
        not_allowed("case: missing value after 'when'")
      else:
        whens.add(input)  # Add the when value
        state = CsWhenValue
    
    of CsWhenValue:
      # After when value - could be body content, next when, or else
      if input == nil:
        # End of input - finalize current when with empty body
        whens.add(new_stream_value(current_body))
        current_body = @[]
      elif input == "when".to_symbol_value():
        # New when clause - save current body
        whens.add(new_stream_value(current_body))
        current_body = @[]
        state = CsWhen
      elif input == "else".to_symbol_value():
        # Else clause - save current body
        whens.add(new_stream_value(current_body))
        current_body = @[]
        state = CsElse
      else:
        # Body content
        current_body.add(input)
        state = CsWhenBody
    
    of CsWhenBody:
      if input == nil:
        # End of input - finalize current when
        whens.add(new_stream_value(current_body))
        current_body = @[]
      elif input == "when".to_symbol_value():
        # New when clause
        whens.add(new_stream_value(current_body))
        current_body = @[]
        state = CsWhen
      elif input == "else".to_symbol_value():
        # Else clause
        whens.add(new_stream_value(current_body))
        current_body = @[]
        state = CsElse
      else:
        current_body.add(input)
    
    of CsElse:
      if input == nil:
        # End of input
        discard
      else:
        else_body.add(input)
  
  for item in self.children:
    handler(item)
  handler(nil)
  
  # Store when clauses as array
  self.props[CASE_WHEN_KEY.to_key()] = new_array_value(whens)
  
  # Store else body (empty stream if not provided)
  if else_body.len > 0:
    self.props[CASE_ELSE_KEY.to_key()] = new_stream_value(else_body)
  else:
    # Default else returns nil
    self.props[CASE_ELSE_KEY.to_key()] = new_stream_value(@[NIL])
  
  self.children.reset  # Clear children as they're now in props
