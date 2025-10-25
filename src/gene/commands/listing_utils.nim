import strutils

import ../types

proc formatValue*(value: Value): string =
  case value.kind
  of VkNil:
    result = "nil"
  of VkBool:
    result = if value == TRUE: "true" else: "false"
  of VkInt:
    result = $value.to_int()
  of VkFloat:
    result = $value.to_float()
  of VkChar:
    result = "'" & $value.char & "'"
  of VkString:
    result = "\"" & value.str & "\""
  of VkSymbol:
    result = value.str
  else:
    result = $value

proc instructionName(kind: InstructionKind): string =
  let name = $kind
  if name.len >= 2 and name.startsWith("Ik"):
    return name[2..^1]
  name

proc formatInstruction*(inst: Instruction, index: int, format: string, show_addresses: bool): string =
  let kindName = instructionName(inst.kind)
  case format
  of "bytecode":
    # Raw bytecode format
    result = kindName
    case inst.kind
    # Instructions with no arguments
    of IkNoop, IkEnd, IkScopeEnd, IkSelf, IkSetSelf, IkRotate, IkParse, IkRender,
       IkEval, IkPushNil, IkPushSelf, IkPop, IkDup, IkDup2, IkDupSecond, IkSwap,
       IkOver, IkLen, IkArrayStart, IkArrayEnd, IkMapStart,
       IkMapEnd, IkGeneStart, IkGeneEnd, IkGeneSetType, IkGeneAddChild,
       IkGetChildDynamic, IkGetMemberOrNil, IkGetMemberDefault, IkAdd, IkSub,
       IkMul, IkDiv, IkLt, IkLe, IkGt, IkGe, IkEq, IkNe, IkAnd, IkOr, IkNot,
       IkNeg, IkCreateRange, IkCreateEnum, IkEnumAddMember, IkReturn,
       IkThrow, IkCatchEnd, IkCatchRestore, IkFinally, IkFinallyEnd,
       IkLoopStart, IkLoopEnd, IkNew, IkGetClass, IkIsInstance, IkSuper,
       IkCallerEval, IkAsync, IkAwait, IkAsyncStart, IkAsyncEnd, IkCompileInit,
       IkCallInit, IkStart, IkImport, IkPow:
      discard
    # Instructions with arg0
    of IkPushValue, IkScopeStart, IkVar, IkVarResolve, IkVarAssign,
       IkResolveSymbol, IkJump, IkJumpIfFalse, IkContinue, IkBreak,
       IkGeneStartDefault, IkSubValue, IkAddValue, IkLtValue, IkFunction,
       IkMacro, IkBlock, IkCompileFn, IkNamespace, IkNamespaceStore,
       IkClass, IkSubClass, IkDefineMethod, IkResolveMethod,
       IkAssign, IkData:
      result &= " " & $inst.arg0
    of IkSetMember, IkGetMember:
      let key = inst.arg0.Key
      let symbol_value = cast[Value](key)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= " " & get_symbol(symbol_index.int)
    of IkMapSetProp, IkGeneSetProp:
      let key = inst.arg0.Key
      let symbol_value = cast[Value](key)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= " " & get_symbol(symbol_index.int)
    of IkSetChild, IkGetChild:
      result &= " " & $inst.arg0.int64
    # Instructions with both args
    of IkVarValue, IkVarResolveInherited, IkVarAssignInherited,
       IkJumpIfMatchSuccess, IkTryStart, IkTryEnd, IkCatchStart:
      result &= " " & $inst.arg0
      if inst.arg1 != 0:
        result &= " " & $inst.arg1
    else:
      # Fallback for any unhandled instructions
      if inst.arg0.kind != VkNil:
        result &= " " & $inst.arg0
      if inst.arg1.kind != VkNil:
        result &= " " & $inst.arg1
  of "compact":
    result = $inst
  else:
    # Pretty format
    if show_addresses:
      result = index.toHex(4) & "  "
    else:
      result = "  "

    result &= kindName.alignLeft(20)

    case inst.kind
    of IkNoop, IkEnd, IkScopeEnd, IkSelf, IkSetSelf, IkRotate, IkParse, IkRender,
       IkEval, IkPushNil, IkPushSelf, IkPop, IkDup, IkDup2, IkDupSecond, IkSwap,
       IkOver, IkLen, IkArrayStart, IkArrayEnd, IkMapStart,
       IkMapEnd, IkGeneStart, IkGeneEnd, IkGeneSetType, IkGeneAddChild,
       IkGetChildDynamic, IkGetMemberOrNil, IkGetMemberDefault, IkAdd, IkSub,
       IkMul, IkDiv, IkLt, IkLe, IkGt, IkGe, IkEq, IkNe, IkAnd, IkOr, IkNot,
       IkNeg, IkCreateRange, IkCreateEnum, IkEnumAddMember, IkReturn,
       IkThrow, IkCatchEnd, IkCatchRestore, IkFinally, IkFinallyEnd,
       IkLoopStart, IkLoopEnd, IkNew, IkGetClass, IkIsInstance, IkSuper,
       IkCallerEval, IkAsync, IkAwait, IkAsyncStart, IkAsyncEnd, IkCompileInit,
       IkCallInit:
      discard

    of IkData, IkPushValue:
      result &= formatValue(inst.arg0)
    of IkScopeStart:
      if inst.arg0.kind == VkScopeTracker:
        result &= "<scope>"
      elif inst.arg0.kind != VkNil:
        result &= formatValue(inst.arg0)
    of IkVar, IkVarResolve, IkVarAssign:
      if inst.arg0.kind == VkInt:
        result &= "var[" & $inst.arg0.int64 & "]"
      else:
        result &= formatValue(inst.arg0)
    of IkResolveSymbol:
      if inst.arg0.kind == VkSymbol:
        result &= inst.arg0.str
      else:
        result &= formatValue(inst.arg0)
    of IkSetMember, IkGetMember:
      let key = inst.arg0.Key
      let symbol_value = cast[Value](key)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= "." & get_symbol(symbol_index.int)
    of IkSetChild, IkGetChild:
      result &= "[" & $inst.arg0.int64 & "]"
    of IkJump, IkJumpIfFalse:
      result &= "-> " & inst.arg0.int64.toHex(4)
    of IkContinue, IkBreak:
      if inst.arg0.int64 == -1:
        result &= "<error>"
      else:
        result &= "label=" & $inst.arg0.int64
    of IkMapSetProp, IkGeneSetProp:
      let key = inst.arg0.Key
      let symbol_value = cast[Value](key)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= "^" & get_symbol(symbol_index.int)
    of IkGeneStartDefault:
      if inst.arg0.kind == VkInt:
        result &= "size=" & $inst.arg0.int64
    of IkSubValue, IkAddValue:
      result &= formatValue(inst.arg0)
    of IkLtValue:
      result &= "< " & formatValue(inst.arg0)
    of IkFunction, IkMacro, IkBlock, IkCompileFn:
      if inst.arg0.kind != VkNil:
        result &= formatValue(inst.arg0)
    of IkNamespace:
      if inst.arg0.kind in {VkString, VkSymbol}:
        result &= inst.arg0.str
      else:
        result &= formatValue(inst.arg0)
    of IkNamespaceStore:
      if inst.arg0.kind == VkSymbol:
        result &= inst.arg0.str
      else:
        result &= formatValue(inst.arg0)
    of IkClass, IkSubClass:
      if inst.arg0.kind == VkString:
        result &= inst.arg0.str
      else:
        result &= formatValue(inst.arg0)
    of IkDefineMethod, IkResolveMethod:
      if inst.arg0.kind == VkSymbol:
        result &= inst.arg0.str
      else:
        result &= formatValue(inst.arg0)
    of IkImport, IkStart, IkPow:
      discard

    of IkVarValue:
      result &= formatValue(inst.arg0) & " -> var[" & $inst.arg1 & "]"
    of IkVarResolveInherited, IkVarAssignInherited:
      result &= "var[" & $inst.arg0.int64 & "] up=" & $inst.arg1
    of IkJumpIfMatchSuccess:
      result &= "index=" & $inst.arg0.int64 & " -> " & inst.arg1.toHex(4)
    of IkTryStart:
      result &= "catch=" & inst.arg0.int64.toHex(4)
      if inst.arg1 != 0:
        result &= " finally=" & inst.arg1.toHex(4)
    of IkTryEnd:
      discard
    of IkCatchStart:
      if inst.arg0.kind != VkNil:
        result &= "type=" & formatValue(inst.arg0)
    of IkAssign:
      if inst.arg0.kind == VkSymbol:
        result &= inst.arg0.str & " ="
      else:
        result &= formatValue(inst.arg0)
    else:
      var shown = false
      if inst.arg0.kind != VkNil:
        result &= formatValue(inst.arg0)
        shown = true
      if inst.arg1.kind != VkNil:
        if shown:
          result &= " "
        result &= formatValue(inst.arg1)
