import std/tables
import ../types
import ../types/core

type
  NativeFnSig* = object
    argTypes*: seq[CallArgType]
    returnType*: CallReturnType

var native_fn_sigs* = initTable[pointer, NativeFnSig]()

proc register_native_sig*(fn: NativeFn, argTypes: seq[CallArgType], returnType: CallReturnType) =
  native_fn_sigs[cast[pointer](fn)] = NativeFnSig(argTypes: argTypes, returnType: returnType)

proc lookup_native_sig*(fn: NativeFn, sig: var NativeFnSig): bool =
  let key = cast[pointer](fn)
  if key in native_fn_sigs:
    sig = native_fn_sigs[key]
    return true
  false

proc release_descriptors*(descs: seq[CallDescriptor]) =
  for desc in descs:
    release(desc.callable)

const
  NativeCtxOffsetVm* = int32(offsetof(NativeContext, vm))
  NativeCtxOffsetTrampoline* = int32(offsetof(NativeContext, trampoline))
  NativeCtxOffsetDescriptors* = int32(offsetof(NativeContext, descriptors))
  NativeCtxOffsetDescriptorCount* = int32(offsetof(NativeContext, descriptor_count))

static:
  assert NativeCtxOffsetVm == 0
  when sizeof(pointer) == 8:
    assert NativeCtxOffsetTrampoline == 8
    assert NativeCtxOffsetDescriptors == 16
    assert NativeCtxOffsetDescriptorCount == 24
  else:
    assert NativeCtxOffsetTrampoline == int32(sizeof(pointer))
    assert NativeCtxOffsetDescriptors == int32(sizeof(pointer) * 2)
    assert NativeCtxOffsetDescriptorCount == int32(sizeof(pointer) * 3)
