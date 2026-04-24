import strformat, strutils

import ./type_defs
import ./core

type
  InstructionOperandKind* = enum
    IokNone
    IokValue
    IokKey
    IokLabel
    IokPc
    IokLocalIndex
    IokParentDepth
    IokCount
    IokFlags
    IokTypeId
    IokMethodName
    IokSelector
    IokCompiledUnit

  InstructionStackEffectKind* = enum
    SekFixed
    SekDynamic
    SekUnknown

  InstructionStackEffect* = object
    min_pops*: int
    pushes*: int
    kind*: InstructionStackEffectKind
    note*: string

type InstructionMetadata* = object
  stack*: InstructionStackEffect
  arg0*: InstructionOperandKind
  arg1*: InstructionOperandKind
  touches_refs*: bool
  lifetime_note*: string
  debug_format*: string
  family*: string
  checked*: bool

proc fixed(min_pops, pushes: int, note = ""): InstructionStackEffect =
  InstructionStackEffect(min_pops: min_pops, pushes: pushes, kind: SekFixed, note: note)

proc dynamic(min_pops: int, note: string): InstructionStackEffect =
  InstructionStackEffect(min_pops: min_pops, pushes: 0, kind: SekDynamic, note: note)

proc meta(stack: InstructionStackEffect, family: string,
          arg0 = IokNone, arg1 = IokNone, touches_refs = false,
          lifetime_note = "", checked = true): InstructionMetadata =
  InstructionMetadata(
    stack: stack,
    arg0: arg0,
    arg1: arg1,
    touches_refs: touches_refs,
    lifetime_note: lifetime_note,
    debug_format: "",
    family: family,
    checked: checked,
  )

proc instruction_metadata*(kind: InstructionKind): InstructionMetadata =
  case kind
  of IkNoop:
    meta(fixed(0, 0), "control")
  of IkData:
    meta(fixed(0, 0), "metadata", IokValue, touches_refs = true)
  of IkStart, IkEnd:
    meta(fixed(0, 0), "control")
  of IkScopeStart:
    meta(fixed(0, 0), "scope", IokValue, touches_refs = true, lifetime_note = "creates a runtime scope")
  of IkScopeEnd:
    meta(fixed(0, 0), "scope", touches_refs = true, lifetime_note = "frees current runtime scope")
  of IkPushValue:
    meta(fixed(0, 1), "stack", IokValue, touches_refs = true)
  of IkPushNil:
    meta(fixed(0, 1), "stack")
  of IkPushTypeValue:
    meta(fixed(0, 1), "stack", IokTypeId)
  of IkPop:
    meta(fixed(1, 0), "stack", touches_refs = true)
  of IkDup:
    meta(fixed(1, 2), "stack", touches_refs = true)
  of IkDup2:
    meta(fixed(2, 4), "stack", touches_refs = true)
  of IkDupSecond, IkOver:
    meta(fixed(2, 3), "stack", touches_refs = true)
  of IkSwap:
    meta(fixed(2, 2), "stack")
  of IkLen:
    meta(fixed(1, 1), "stack")
  of IkVar, IkVarValue:
    meta(fixed(1, 0), "variables", IokLocalIndex, arg1 = IokTypeId, touches_refs = true)
  of IkVarResolve:
    meta(fixed(0, 1), "variables", IokLocalIndex, touches_refs = true)
  of IkVarResolveInherited:
    meta(fixed(0, 1), "variables", IokLocalIndex, IokParentDepth, touches_refs = true)
  of IkVarAssign:
    meta(fixed(1, 0), "variables", IokLocalIndex, touches_refs = true)
  of IkVarAssignInherited:
    meta(fixed(1, 0), "variables", IokLocalIndex, IokParentDepth, touches_refs = true)
  of IkAssign:
    meta(fixed(1, 0), "variables", IokValue, touches_refs = true)
  of IkJump, IkJumpIfFalse, IkContinue, IkBreak:
    meta(dynamic(0, "control-flow target may be a label before optimization or a pc after optimization"),
      "control", IokPc)
  of IkJumpIfMatchSuccess:
    meta(dynamic(0, "argument matching decides whether the jump is taken"), "control", IokValue, IokPc)
  of IkLoopStart, IkLoopEnd:
    meta(fixed(0, 0), "control")
  of IkAdd, IkSub, IkMul, IkDiv, IkMod, IkPow,
     IkLt, IkLe, IkGt, IkGe, IkEq, IkNe,
     IkAnd, IkOr, IkXor, IkShl, IkShr:
    meta(fixed(2, 1), "operators")
  of IkAddValue, IkSubValue, IkVarAddValue, IkVarSubValue, IkVarMulValue,
     IkVarDivValue, IkVarModValue, IkLtValue, IkVarLtValue, IkVarLeValue,
     IkVarGtValue, IkVarGeValue, IkVarEqValue:
    meta(fixed(1, 1), "operators", IokValue)
  of IkIncVar, IkDecVar:
    meta(fixed(0, 0), "operators", IokLocalIndex)
  of IkNeg, IkNot, IkTypeOf, IkIsType:
    meta(fixed(1, 1), "operators", arg1 = IokTypeId)
  of IkCreateRange:
    meta(fixed(3, 1), "collections", touches_refs = true)
  of IkCreateEnum:
    meta(dynamic(1, "enum creation consumes a variable shape"), "types", touches_refs = true)
  of IkEnumAddMember:
    meta(dynamic(1, "enum member creation uses enum state and stack operands"), "types", touches_refs = true)
  of IkCompileInit:
    meta(fixed(0, 0), "module")
  of IkThrow:
    meta(fixed(1, 0), "exception", touches_refs = true)
  of IkTryStart:
    meta(fixed(0, 0), "exception", IokPc, IokPc, lifetime_note = "pushes an exception handler")
  of IkTryEnd, IkCatchStart, IkCatchEnd, IkFinally, IkFinallyEnd, IkCatchRestore:
    meta(dynamic(0, "exception state controls stack and handler effects"), "exception", touches_refs = true)
  of IkGetClass, IkIsInstance:
    meta(fixed(1, 1), "types", touches_refs = true)
  of IkNamespace, IkImport, IkNamespaceStore:
    meta(dynamic(0, "module and namespace instructions use runtime namespace state"),
      "module", IokValue, IokFlags, touches_refs = true)
  of IkFunction, IkBlock:
    meta(fixed(0, 1), "functions", IokValue, touches_refs = true)
  of IkReturn:
    meta(dynamic(0, "return unwinds the current frame"), "control", touches_refs = true)
  of IkYield:
    meta(dynamic(0, "yield suspends generator state"), "control", touches_refs = true)
  of IkClass, IkSubClass:
    meta(dynamic(0, "class creation consumes declaration metadata"), "class", IokValue, IokFlags, touches_refs = true)
  of IkNew:
    meta(dynamic(1, "constructor invocation consumes target and arguments"), "class", touches_refs = true)
  of IkResolveMethod:
    meta(fixed(1, 1), "class", IokMethodName, touches_refs = true)
  of IkInterface, IkInterfaceMethod, IkInterfaceProp, IkImplement, IkImplementMethod, IkImplementCtor, IkAdapter:
    meta(dynamic(0, "interface/adapter metadata is staged for checked execution"), "interface",
      IokValue, IokFlags, touches_refs = true, checked = false)
  of IkCallInit, IkDefineMethod, IkDefineConstructor, IkDefineProp,
     IkCallSuperMethod, IkCallSuperMethodMacro, IkCallSuperMethodKw,
     IkCallSuperCtor, IkCallSuperCtorMacro, IkCallSuperCtorKw, IkSuper:
    meta(dynamic(0, "class and super dispatch consume declaration/call state"), "class",
      IokMethodName, IokFlags, touches_refs = true)
  of IkMapStart, IkHashMapStart, IkArrayStart, IkStreamStart:
    meta(fixed(0, 0), "collections", lifetime_note = "records collection base")
  of IkMapSetProp:
    meta(fixed(1, 0), "collections", IokKey, touches_refs = true)
  of IkMapSetPropValue:
    meta(fixed(0, 0), "collections", IokKey, touches_refs = true)
  of IkMapSpread, IkArrayAddSpread, IkStreamAddSpread, IkGenePropsSpread, IkGeneAddSpread:
    meta(fixed(1, 0), "collections", touches_refs = true)
  of IkMapEnd, IkHashMapEnd, IkArrayEnd, IkStreamEnd:
    meta(dynamic(0, "collection end consumes values since the recorded collection base"), "collections", arg1 = IokFlags, touches_refs = true)
  of IkGeneStart, IkGeneStartDefault:
    meta(dynamic(0, "gene start records collection base and may use a default type label"), "gene", IokPc, touches_refs = true)
  of IkGeneSetType:
    meta(fixed(1, 0), "gene", touches_refs = true)
  of IkGeneSetProp:
    meta(fixed(1, 0), "gene", IokKey, touches_refs = true)
  of IkGeneSetPropValue:
    meta(fixed(0, 0), "gene", IokKey, touches_refs = true)
  of IkGeneAddChild, IkGeneAdd:
    meta(fixed(1, 0), "gene", touches_refs = true)
  of IkGeneAddChildValue:
    meta(fixed(0, 0), "gene", IokValue, touches_refs = true)
  of IkGeneEnd:
    meta(dynamic(0, "gene end consumes values since the recorded gene base"), "gene", arg1 = IokFlags, touches_refs = true)
  of IkRepeatInit, IkRepeatDecCheck:
    meta(dynamic(1, "repeat loop updates counter state"), "control", IokPc)
  of IkTailCall:
    meta(dynamic(1, "legacy tail call consumes callee and arguments"), "calls", touches_refs = true, checked = false)
  of IkUnifiedCall0:
    meta(dynamic(1, "call consumes call-base target and zero args"), "calls", touches_refs = true)
  of IkUnifiedCall1:
    meta(dynamic(2, "call consumes call-base target and one arg"), "calls", touches_refs = true)
  of IkUnifiedCall:
    meta(dynamic(1, "call consumes call-base target and arg1 positional args"), "calls", arg1 = IokCount, touches_refs = true)
  of IkUnifiedCallKw:
    meta(dynamic(1, "call consumes keyword and positional args described by arg0/arg1"), "calls", IokCount, IokCount, touches_refs = true)
  of IkUnifiedCallDynamic:
    meta(dynamic(1, "dynamic call consumes arguments since call base"), "calls", touches_refs = true)
  of IkUnifiedMethodCall0, IkUnifiedMethodCall1, IkUnifiedMethodCall2, IkUnifiedMethodCall,
     IkUnifiedMethodCallKw, IkDynamicMethodCall:
    meta(dynamic(1, "method call consumes receiver and argument state"), "calls", IokMethodName, IokCount, touches_refs = true)
  of IkCallArgsStart:
    meta(fixed(1, 1), "calls", lifetime_note = "pushes a call base")
  of IkCallArgSpread:
    meta(fixed(1, 0), "calls", touches_refs = true)
  of IkResolveSymbol:
    meta(fixed(0, 1), "lookup", IokKey, touches_refs = true)
  of IkSetMember, IkSetMemberDynamic:
    meta(fixed(2, 1), "lookup", IokKey, touches_refs = true)
  of IkGetMember, IkGetMemberOrNil, IkGetMemberDefault:
    meta(fixed(1, 1), "lookup", IokKey, touches_refs = true)
  of IkSetChild:
    meta(fixed(2, 1), "lookup", IokCount, touches_refs = true)
  of IkGetChild:
    meta(fixed(1, 1), "lookup", IokCount, touches_refs = true)
  of IkGetChildDynamic:
    meta(fixed(2, 1), "lookup", touches_refs = true)
  of IkSelf, IkSetSelf:
    meta(fixed(0, 1), "frame", touches_refs = true)
  of IkRotate:
    meta(fixed(3, 3), "stack")
  of IkParse, IkEval, IkCallerEval, IkRender:
    meta(fixed(1, 1), "runtime", touches_refs = true)
  of IkAsync:
    meta(fixed(1, 1), "async", touches_refs = true)
  of IkAsyncStart, IkAsyncEnd, IkAwait:
    meta(dynamic(0, "async state controls stack and exception effects"), "async", IokValue, IokFlags, touches_refs = true)
  of IkTryUnwrap:
    meta(fixed(1, 1), "control", touches_refs = true)
  of IkMatchGeneType:
    meta(fixed(1, 1), "pattern", IokValue)
  of IkGetGeneChild:
    meta(fixed(1, 1), "pattern", IokCount, touches_refs = true)
  of IkSpawnThread:
    meta(dynamic(2, "thread execution is staged outside checked VM MVP"), "thread", touches_refs = true, checked = false)
  of IkPushCallPop, IkLoadCallPop, IkGetLocal, IkSetLocal, IkAddLocal, IkIncLocal,
     IkDecLocal, IkReturnNil, IkReturnTrue, IkReturnFalse, IkResume:
    meta(dynamic(0, "superinstruction stack effects are checked by targeted runtime hooks"), "superinstruction", touches_refs = true)
  of IkAssertValue:
    meta(fixed(1, 1), "selector")
  of IkValidateSelectorSegment:
    meta(fixed(1, 1), "selector")
  of IkCreateSelector:
    meta(dynamic(0, "selector consumes arg1 segments from the stack"), "selector", arg1 = IokCount, touches_refs = true)
  of IkExport:
    meta(fixed(0, 0), "module", IokValue, touches_refs = true)
  of IkVmDurationStart:
    meta(fixed(0, 0), "vm")
  of IkVmDuration:
    meta(fixed(0, 1), "vm")
  of IkVarDestructure:
    meta(dynamic(1, "destructuring consumes one value and writes multiple locals"), "variables", IokValue, touches_refs = true)

proc instruction_stack_effect*(inst: Instruction): InstructionStackEffect =
  result = instruction_metadata(inst.kind).stack
  case inst.kind
  of IkUnifiedCall:
    result.min_pops = max(1, inst.arg1.int + 1)
  of IkUnifiedCallKw:
    result.min_pops = max(1, inst.arg1.int + 1)
  of IkUnifiedMethodCall:
    result.min_pops = max(1, inst.arg1.int + 1)
  of IkUnifiedMethodCallKw:
    result.min_pops = max(1, inst.arg1.int + 1)
  of IkDynamicMethodCall:
    result.min_pops = max(2, inst.arg1.int + 2)
  of IkCreateSelector:
    result.min_pops = max(0, inst.arg1.int)
  else:
    discard

proc metadata_gap_kinds*(): seq[InstructionKind] =
  for kind in InstructionKind:
    if not instruction_metadata(kind).checked:
      result.add(kind)

proc hex_label(label: Label): string =
  fmt"{label.int32:04X}"

proc operand_to_string(kind: InstructionOperandKind, value: Value, arg1: int32): string =
  case kind
  of IokNone:
    ""
  of IokLabel:
    if value.kind == VkInt: hex_label(value.int64.Label) else: $value
  of IokPc, IokLocalIndex, IokParentDepth, IokCount, IokFlags, IokTypeId:
    $arg1
  of IokKey:
    $value
  else:
    $value

proc arg0_to_string(kind: InstructionOperandKind, inst: Instruction): string =
  case kind
  of IokNone:
    ""
  of IokPc, IokLabel:
    if inst.arg0.kind == VkInt: hex_label(inst.arg0.int64.Label) else: $inst.arg0
  else:
    operand_to_string(kind, inst.arg0, inst.arg1)

proc arg1_to_string(kind: InstructionOperandKind, inst: Instruction): string =
  case kind
  of IokNone:
    ""
  of IokPc, IokLabel:
    hex_label(inst.arg1.Label)
  else:
    $inst.arg1

proc format_instruction_debug*(inst: Instruction): string =
  let metadata = instruction_metadata(inst.kind)
  let label_prefix =
    if inst.label.int > 0: hex_label(inst.label)
    else: "        "
  let opcode = ($inst.kind)[2..^1].alignLeft(20)
  var parts = @[label_prefix & " " & opcode]
  let arg0 = arg0_to_string(metadata.arg0, inst)
  if arg0.len > 0:
    parts.add(arg0)
  let arg1 = arg1_to_string(metadata.arg1, inst)
  if arg1.len > 0:
    parts.add(arg1)
  parts.join(" ")
