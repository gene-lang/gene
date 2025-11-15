import math, hashes, tables, sets, re, bitops, unicode, strutils, strformat
import random
import dynlib
import times
import os
import asyncdispatch  # For async I/O support

# Forward declarations for new types
type
  Value* {.bycopy, shallow.} = distinct int64  # No copy/destroy hooks needed for POD type
  CustomValue* = ref object of RootObj

type
  Mixin* = ref object
  EnumDef* = ref object
    name*: string
    members*: Table[string, EnumMember]

  EnumMember* = ref object
    parent*: Value  # The enum this member belongs to
    name*: string
    value*: int

  FutureState* = enum
    FsPending
    FsSuccess
    FsFailure

  FutureObj* = ref object
    state*: FutureState
    value*: Value              # Result value or exception
    success_callbacks*: seq[Value]  # Success callback functions
    failure_callbacks*: seq[Value]  # Failure callback functions
    nim_future*: Future[Value]  # Underlying Nim async future (nil for sync futures)

  GeneratorState* = enum
    GsPending            # Not yet started
    GsRunning            # Currently executing
    GsSuspended          # Suspended at yield
    GsDone               # Exhausted

  ExceptionData* = ref object
  Interception* = ref object

  # Threading support types
  ThreadMessageType* = enum
    MtSend          # Send data, no reply expected
    MtSendWithReply # Send data, expect reply
    MtRun           # Run code, no reply expected
    MtRunWithReply  # Run code, expect reply
    MtReply         # Reply to previous message
    MtTerminate     # Terminate thread

  ThreadState* = enum
    TsUninitialized  # Thread slot not initialized
    TsFree           # Thread slot available
    TsBusy           # Thread is running

  Thread* = ref object
    id*: int              # Thread ID (index in THREADS array)
    secret*: int          # Secret for validation

  ThreadMessage* = ref object
    id*: int                    # Unique message ID
    msg_type*: ThreadMessageType    # Type of message (renamed to avoid 'type' keyword)
    payload*: Value             # Data payload
    code*: Value                # Gene AST to compile and execute (not bytecode!)
    from_message_id*: int       # For MtReply
    from_thread_id*: int        # Sender thread ID
    from_thread_secret*: int    # Sender thread secret
    handled*: bool              # For user callbacks

  NativeFn2* = proc(vm_data: pointer, args: Value): Value {.gcsafe.}

type
  ValueKind* {.size: sizeof(int16) .} = enum
    # Core types
    VkNil = 0
    VkVoid
    VkPlaceholder
    VkPointer

    # Any and Custom types for extensibility
    VkAny
    VkCustom

    # Basic data types
    VkBool
    VkInt
    VkRatio              # Rational numbers
    VkFloat
    VkBin                # Binary data with bit size
    VkBin64              # 64-bit binary with bit size
    VkByte               # Single byte with bit size
    VkBytes              # Byte sequences
    VkChar               # Unicode characters
    VkString
    VkSymbol
    VkComplexSymbol

    # Pattern and regex types
    VkRegex
    VkRegexMatch
    VkRange
    VkSelector

    # Async types
    VkFuture             # Async future/promise
    VkGenerator          # Generator instance
    VkThread             # Thread reference
    VkThreadMessage      # Thread message

    # Date and time types
    VkDate               # Date only
    VkDateTime           # Date + time + timezone
    VkTime               # Time only
    VkTimezone           # Timezone info

    # Collection types
    VkArray              # For backward compatibility, will alias to VkVector
    VkVector             # Main sequence type
    VkSet
    VkMap
    VkGene
    VkStream
    VkDocument

    # File system types
    VkFile
    VkArchiveFile
    VkDirectory

    # Meta-programming types
    VkQuote
    VkUnquote
    VkReference
    VkRefTarget

    # Language construct types
    VkApplication
    VkPackage
    VkModule
    VkNamespace
    VkFunction
    VkCompileFn
    VkBlock
    VkClass
    VkMixin              # For mixin support
    VkMethod
    VkBoundMethod
    VkSuper
    VkInstance
    VkCast               # Type casting
    VkEnum
    VkEnumMember
    VkNativeFn
    VkNativeFn2
    VkNativeMethod
    VkNativeMethod2

    # Exception handling
    VkException = 128    # Start exceptions at 128
    VkInterception       # AOP interception

    # Concurrency types

    # JSON integration
    VkJson               # JSON values
    VkNativeFile         # Native file handles

    # Internal VM types
    VkCompiledUnit
    VkInstruction
    VkScopeTracker
    VkFunctionDef
    VkScope
    VkFrame
    VkNativeFrame

  Key* = distinct int64

  ScopeTrackerSnapshot* = ref object
    next_index*: int16
    parent_index_max*: int16
    scope_started*: bool
    mappings*: seq[(Key, int16)]
    parent*: ScopeTrackerSnapshot

  FunctionDefInfo* = ref object
    scope_tracker*: ScopeTracker
    compiled_body*: Value

  # Extended Reference type supporting all ValueKind variants
  Reference* = object
    case kind*: ValueKind
      # Basic string-like types
      of VkString, VkSymbol:
        str*: string
      of VkComplexSymbol:
        csymbol*: seq[string]

      # Numeric and binary types
      of VkRatio:
        ratio_num*: int64
        ratio_denom*: int64
      of VkBin:
        bin_data*: seq[uint8]
        bin_bit_size*: uint
      of VkBin64:
        bin64_data*: uint64
        bin64_bit_size*: uint
      of VkByte:
        byte_data*: uint8
        byte_bit_size*: uint
      of VkBytes:
        bytes_data*: seq[uint8]

      # Pattern and regex types
      of VkRegex:
        regex_pattern*: string
        regex_flags*: uint8
      of VkRegexMatch:
        regex_match_data*: seq[string]  # Simplified match data
      of VkRange:
        range_start*: Value
        range_end*: Value
        range_step*: Value
      of VkSelector:
        selector_pattern*: string
        selector_path*: seq[Value]

      # Date and time types
      of VkDate:
        date_year*: int16
        date_month*: int8
        date_day*: int8
      of VkDateTime:
        dt_year*: int16
        dt_month*: int8
        dt_day*: int8
        dt_hour*: int8
        dt_minute*: int8
        dt_second*: int8
        dt_timezone*: int16
      of VkTime:
        time_hour*: int8
        time_minute*: int8
        time_second*: int8
        time_microsecond*: int32
      of VkTimezone:
        tz_offset*: int16
        tz_name*: string

      # Collection types
      of VkArray, VkVector:
        arr*: seq[Value]
      of VkSet:
        set*: HashSet[Value]
      of VkMap:
        map*: Table[Key, Value]
      of VkStream:
        stream*: seq[Value]
        stream_index*: int64
        stream_ended*: bool
      of VkDocument:
        doc*: Document

      # File system types
      of VkFile:
        file_path*: string
        file_content*: seq[uint8]
        file_permissions*: uint16
      of VkArchiveFile:
        arc_path*: string
        arc_members*: Table[string, Value]
      of VkDirectory:
        dir_path*: string
        dir_members*: Table[string, Value]

      # Meta-programming types
      of VkQuote:
        quote*: Value
      of VkUnquote:
        unquote*: Value
        unquote_discard*: bool
      of VkReference:
        ref_target*: Value
      of VkRefTarget:
        target_id*: int64
      of VkFuture:
        future*: FutureObj
      of VkGenerator:
        generator*: GeneratorObj  # Store the generator ref object directly
      of VkThread:
        thread*: Thread
      of VkThreadMessage:
        thread_message*: ThreadMessage

      # Language constructs
      of VkApplication:
        app*: Application
      of VkPackage:
        pkg*: Package
      of VkModule:
        module*: Module
      of VkNamespace:
        ns*: Namespace
      of VkFunction:
        fn*: Function
      of VkCompileFn:
        `compile_fn`*: CompileFn
      of VkBlock:
        `block`*: Block
      of VkClass:
        class*: Class
      of VkMixin:
        `mixin`*: Mixin
      of VkMethod:
        `method`*: Method
      of VkBoundMethod:
        bound_method*: BoundMethod
      of VkSuper:
        super_instance*: Value
        super_class*: Class
      of VkInstance:
        instance_class*: Class
        instance_props*: Table[Key, Value]
      of VkCast:
        cast_value*: Value
        cast_class*: Class
      of VkEnum:
        enum_def*: EnumDef
      of VkEnumMember:
        enum_member*: EnumMember
      of VkNativeFn:
        native_fn*: NativeFn
      of VkNativeFn2:
        native_fn2*: NativeFn2
      of VkNativeMethod, VkNativeMethod2:
        native_method*: NativeFn

      of VkException:
        exception_data*: ExceptionData
      of VkInterception:
        interception*: Interception

      # Concurrency types

      # JSON and file types
      of VkJson:
        json_data*: string  # Serialized JSON
      of VkNativeFile:
        native_file*: File

      # Internal VM types
      of VkCompiledUnit:
        cu*: CompilationUnit
      of VkInstruction:
        instr*: Instruction
      of VkScopeTracker:
        scope_tracker*: ScopeTracker
      of VkFunctionDef:
        function_def*: FunctionDefInfo
      of VkScope:
        scope*: Scope
      of VkFrame:
        frame*: Frame
      of VkNativeFrame:
        native_frame*: NativeFrame

      # Any and Custom types
      of VkAny:
        any_data*: pointer
        any_class*: Class
      of VkCustom:
        custom_data*: CustomValue
        custom_class*: Class

      else:
        discard
    ref_count*: int32

  SourceTrace* = ref object
    parent*: SourceTrace
    children*: seq[SourceTrace]
    filename*: string
    line*: int
    column*: int
    child_index*: int

  Gene* = object
    ref_count*: int32
    `type`*: Value
    trace*: SourceTrace
    props*: Table[Key, Value]
    children*: seq[Value]

  String* = object
    ref_count*: int32
    str*: string

  Document* = ref object
    `type`: Value
    props*: Table[Key, Value]
    children*: seq[Value]
    # references*: References # Uncomment this when it's needed.

  ScopeObj* = object
    ref_count*: int32
    tracker*: ScopeTracker
    parent*: Scope
    members*:  seq[Value]
    # Below fields are replacement of seq[Value] to achieve better performance
    #   Have to benchmark to see if it's worth it.
    # vars*: ptr UncheckedArray[Value]
    # vars_in_use*: int16
    # vars_max*: int16

  Scope* = ptr ScopeObj

  ## This is the root of a running application
  Application* = ref object
    name*: string         # Default to base name of command, can be changed, e.g. ($set_app_name "...")
    pkg*: Package         # Entry package for the application
    ns*: Namespace
    cmd*: string
    args*: seq[string]
    main_module*: Module
    # dep_root*: DependencyRoot
    props*: Table[Key, Value]  # Additional properties

    global_ns*     : Value
    gene_ns*       : Value
    genex_ns*      : Value

    object_class*   : Value
    nil_class*      : Value
    bool_class*     : Value
    int_class*      : Value
    float_class*    : Value
    char_class*     : Value
    string_class*   : Value
    symbol_class*   : Value
    complex_symbol_class*: Value
    array_class*    : Value
    map_class*      : Value
    set_class*      : Value
    gene_class*     : Value
    stream_class*   : Value
    document_class* : Value
    regex_class*    : Value
    range_class*    : Value
    date_class*     : Value
    datetime_class* : Value
    time_class*     : Value
    timezone_class* : Value
    selector_class* : Value
    exception_class*: Value
    class_class*    : Value
    mixin_class*    : Value
    application_class*: Value
    package_class*  : Value
    file_class*     : Value
    dir_class*      : Value
    module_class*   : Value
    namespace_class*: Value
    function_class* : Value
    macro_class*    : Value
    block_class*    : Value
    future_class*   : Value
    generator_class*: Value
    thread_class*   : Value
    thread_message_class* : Value
    thread_message_type_class* : Value

  Package* = ref object
    dir*: string          # Where the package assets are installed
    adhoc*: bool          # Adhoc package is created when package.gene is not found
    ns*: Namespace
    name*: string
    version*: Value
    license*: Value
    globals*: seq[string] # Global variables defined by this package
    # dependencies*: Table[Key, Dependency]
    homepage*: string
    src_path*: string     # Default to "src"
    test_path*: string    # Default to "tests"
    asset_path*: string   # Default to "assets"
    build_path*: string   # Default to "build"
    load_paths*: seq[string]
    init_modules*: seq[string]    # Modules that should be loaded when the package is used the first time
    props*: Table[Key, Value]  # Additional properties
    # doc*: Document        # content of package.gene

  SourceType* = enum
    StFile
    StVirtualFile # e.g. a file embeded in the source code or an archive file.
    StInline
    StRepl
    StEval

  Module* = ref object
    source_type*: SourceType
    source*: Value
    pkg*: Package         # Package in which the module is defined
    name*: string
    ns*: Namespace
    handle*: LibHandle    # Optional handle for dynamic lib
    props*: Table[Key, Value]  # Additional properties

  Namespace* = ref object
    module*: Module
    parent*: Namespace
    stop_inheritance*: bool  # When set to true, stop looking up for members from parent namespaces
    name*: string
    members*: Table[Key, Value]
    on_member_missing*: seq[Value]
    version*: uint64  # Incremented on any mutation for cache invalidation

  Class* = ref object
    parent*: Class
    name*: string
    constructor*: Value
    methods*: Table[Key, Method]
    members*: Table[Key, Value]  # Static members - class acts as namespace
    on_extended*: Value
    # method_missing*: Value
    ns*: Namespace # Class can act like a namespace
    for_singleton*: bool # if it's the class associated with a single object, can not be extended
    version*: uint64  # Incremented when methods are mutated
    has_macro_constructor*: bool  # Track if class has macro constructor for validation

  Method* = ref object
    class*: Class
    name*: string
    callable*: Value
    # public*: bool
    is_macro*: bool

  BoundMethod* = object
    self*: Value
    # class*: Class       # Note that class may be different from method.class
    `method`*: Method

  Function* = ref object
    async*: bool
    is_generator*: bool  # True for generator functions
    is_macro_like*: bool  # True for macro-like functions (defined with fn!)
    name*: string
    ns*: Namespace  # the namespace of the module wherein this is defined.
    scope_tracker*: ScopeTracker  # the root scope tracker of the function
    parent_scope*: Scope  # this could be nil if parent scope is empty.
    matcher*: RootMatcher
    # matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: CompilationUnit
    # ret*: Expr

  CompileFn* = ref object
    ns*: Namespace
    name*: string
    scope_tracker*: ScopeTracker
    parent_scope*: Scope
    matcher*: RootMatcher
    # matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: CompilationUnit

  Block* = ref object
    frame*: Frame # The frame wherein the block is defined
    ns*: Namespace
    scope_tracker*: ScopeTracker
    matcher*: RootMatcher
    # matching_hint*: MatchingHint
    body*: seq[Value]
    body_compiled*: CompilationUnit

  MatchingMode* {.size: sizeof(int16) .} = enum
    MatchArguments # (fn f [a b] ...)
    MatchExpression # (match [a b] input): a and b will be defined
    MatchAssignment # ([a b] = input): a and b must be defined first

  # Match the whole input or the first child (if running in ArgumentMode)
  # Can have name, match nothing, or have group of children
  RootMatcher* = ref object
    mode*: MatchingMode
    hint_mode*: MatchingHintMode
    children*: seq[Matcher]

  MatchingHintMode* {.size: sizeof(int16) .} = enum
    MhDefault
    MhNone
    MhSimpleData  # E.g. [a b]

  # MatchingHint* = object
  #   mode*: MatchingHintMode

  MatcherKind* = enum
    MatchType
    MatchProp
    MatchData
    MatchLiteral

  Matcher* = ref object
    root*: RootMatcher
    kind*: MatcherKind
    next*: Matcher  # if kind is MatchData and is_splat is true, we may need to check next matcher
    name_key*: Key
    is_prop*: bool
    literal*: Value # if kind is MatchLiteral, this is required
    # match_name*: bool # Match symbol to name - useful for (myif true then ... else ...)
    default_value*: Value
    # default_value_expr*: Expr
    is_splat*: bool
    min_left*: int # Minimum number of args following this
    children*: seq[Matcher]
    # required*: bool # computed property: true if splat is false and default value is not given

  # MatchedFieldKind* = enum
  #   MfMissing
  #   MfSuccess
  #   MfTypeMismatch # E.g. map is passed but array or gene is expected

  # MatchResult* = object
  #   fields*: seq[MatchedFieldKind]

  Id* = distinct int64
  Label* = int16

  LoopInfo* = object
    start_label*: Label
    end_label*: Label

  MethodAccessMode* = enum
    MamAutoCall
    MamReference

  Compiler* = ref object
    output*: CompilationUnit
    quote_level*: int
    scope_trackers*: seq[ScopeTracker]
    loop_stack*: seq[LoopInfo]
    tail_position*: bool  # Track if we're in tail position for tail call optimization
    eager_functions*: bool
    trace_stack*: seq[SourceTrace]
    last_error_trace*: SourceTrace
    method_access_mode*: MethodAccessMode

  InstructionKind* {.size: sizeof(int16).} = enum
    IkNoop
    IkData    # Data for the previous instruction

    IkStart   # start a compilation unit
    IkEnd     # end a compilation unit

    IkScopeStart
    IkScopeEnd

    IkPushValue   # push value to the next slot
    IkPushNil
    IkPushSelf    # push the current frame's self value
    IkPop
    IkDup         # duplicate top stack element
    IkDup2        # duplicate top two stack elements
    IkDupSecond   # duplicate second element (under top)
    IkSwap        # swap top two stack elements
    IkOver        # copy second element to top: [a b] -> [a b a]
    IkLen         # get length of collection

    IkVar
    IkVarValue
    IkVarResolve
    IkVarResolveInherited
    IkVarAssign
    IkVarAssignInherited

    IkAssign      # TODO: rename to IkSetMemberOnCurrentNS

    IkJump        # unconditional jump
    IkJumpIfFalse

    IkJumpIfMatchSuccess  # Special instruction for argument matching

    IkLoopStart
    IkLoopEnd
    IkContinue    # is added automatically before the loop end
    IkBreak

    IkAdd
    IkAddValue    # args: literal value
    IkVarAddValue # variable + literal value
    IkIncVar      # Increment variable by 1
    IkSub
    IkSubValue
    IkVarSubValue # variable - literal value
    IkDecVar      # Decrement variable by 1
    IkNeg          # Unary negation
    IkMul
    IkVarMulValue # variable * literal value
    IkDiv
    IkVarDivValue # variable / literal value
    IkPow

    IkLt
    IkLtValue
    IkVarLtValue
    IkLe
    IkGt
    IkGe
    IkEq
    IkNe

    IkAnd
    IkOr
    IkNot

    IkCreateRange
    IkCreateEnum
    IkEnumAddMember

    IkCompileInit

    IkThrow
    IkTryStart    # mark start of try block
    IkTryEnd      # mark end of try block
    IkCatchStart  # mark start of catch block
    IkCatchEnd    # mark end of catch block
    IkFinally     # mark start of finally block
    IkFinallyEnd  # mark end of finally block
    IkGetClass    # get the class of a value
    IkIsInstance  # check if value is instance of class
    IkCatchRestore # restore exception for next catch clause

    # IkApplication
    # IkPackage
    # IkModule

    IkNamespace
    IkImport
    IkNamespaceStore

    IkFunction
    IkReturn
    IkYield        # Suspend generator and yield value

    IkCompileFn

    IkMacro

    IkBlock

    IkClass
    IkSubClass
    IkNew
    IkResolveMethod

    IkCallInit
    IkDefineMethod      # Define a method on a class
    IkDefineConstructor # Define a constructor on a class
    IkSuper             # Push the parent method as a bound method

    IkMapStart
    IkMapSetProp        # args: key
    IkMapSetPropValue   # args: key, literal value
    IkMapSpread         # Spread map key-value pairs into current map
    IkMapEnd

    IkArrayStart
    IkArrayAddSpread    # Spread add - pop array and push all elements onto stack
    IkArrayEnd
    IkStreamStart
    IkStreamAddSpread
    IkStreamEnd

    IkGeneStart
    IkGeneStartDefault
    IkGeneSetType
    IkGeneSetProp
    IkGeneSetPropValue        # args: key, literal value
    IkGenePropsSpread         # Spread map key-value pairs into gene properties
    IkGeneAddChild            # Normal add (legacy name, same as IkGeneAdd)
    IkGeneAdd                 # Normal add - add single child to gene
    IkGeneAddChildValue       # args: literal value
    IkGeneAddSpread           # Spread add - unpack array and add all elements as children
    IkGeneEnd

    IkRepeatInit
    IkRepeatDecCheck

    # Legacy tail call instruction (kept for compatibility)
    IkTailCall        # Tail call optimization

    # Unified call instructions
    IkUnifiedCall0      # Zero-argument unified call
    IkUnifiedCall1      # Single-argument unified call
    IkUnifiedCall       # Multi-argument unified call
    IkUnifiedMethodCall0 # Zero-argument method call
    IkUnifiedMethodCall1 # Single-argument method call
    IkUnifiedMethodCall2 # Two-argument method call
    IkUnifiedMethodCall  # Multi-argument method call

    IkResolveSymbol
    IkSetMember
    IkGetMember
    IkGetMemberOrNil    # Get member or return NIL if not found
    IkGetMemberDefault  # Get member or return default value
    IkSetChild
    IkGetChild
    IkGetChildDynamic  # Get child using index from stack

    IkSelf
    IkSetSelf      # Set new self value
    IkRotate       # Rotate top 3 stack elements: [a, b, c] -> [c, a, b]
    IkParse        # Parse string to Gene value
    IkEval         # Evaluate a value
    IkCallerEval   # Evaluate expression in caller's context
    IkRender       # Render a template
    IkAsync        # Wrap value in a Future
    IkAsyncStart   # Start async block with exception handling
    IkAsyncEnd     # End async block and create future
    IkAwait        # Wait for Future to complete

    # Threading
    IkSpawnThread  # Spawn a new thread (pops: return_value flag, CompilationUnit; pushes: thread ref or future)

    # Superinstructions for common patterns
    IkPushCallPop      # PUSH; CALL; POP (common for void function calls)
    IkLoadCallPop      # LOADK; CALL1; POP
    IkGetLocal         # Optimized local variable access
    IkSetLocal         # Optimized local variable set
    IkAddLocal         # GETLOCAL x; ADD; SETLOCAL y
    IkIncLocal         # Increment local variable
    IkDecLocal         # Decrement local variable
    IkReturnNil        # Common pattern: return nil
    IkReturnTrue       # Common pattern: return true
    IkReturnFalse      # Common pattern: return false
    IkResume
    IkVarLeValue
    IkVarGtValue
    IkVarGeValue
    IkVarEqValue

  # Keep the size of Instruction to 2*8 = 16 bytes
  Instruction* = object
    kind*: InstructionKind
    label*: Label
    arg1*: int32
    arg0*: Value

  VarIndex* = object
    local_index*: int32
    parent_index*: int32

  CompilationUnitKind* {.size: sizeof(int8).} = enum
    CkDefault
    CkFunction
    CkCompileFn
    CkBlock
    CkModule
    CkInit      # namespace / class / object initialization
    CkInline    # evaluation during execution

  CompilationUnit* = ref object
    id*: Id
    kind*: CompilationUnitKind
    skip_return*: bool
    matcher*: RootMatcher
    instructions*: seq[Instruction]
    trace_root*: SourceTrace
    instruction_traces*: seq[SourceTrace]
    labels*: Table[Label, int]
    inline_caches*: seq[InlineCache]  # Inline caches indexed by PC

  # Used by the compiler to keep track of scopes and variables
  #
  # Scopes should be created on demand (when the first variable is defined)
  # Scopes should be destroyed when they are no longer needed
  # Scopes should stay alive when they are referenced by child scopes
  # Function/macro/block/if/loop/switch/do/eval inherit parent scope
  # Class/namespace do not inherit parent scope
  ScopeTracker* = ref object
    parent*: ScopeTracker   # If parent is nil, the scope is the top level scope.
    parent_index_max*: int16
    next_index*: int16      # If next_index is 0, the scope is empty
    mappings*: Table[Key, int16]
    scope_started*: bool    # Track if we've added a ScopeStart instruction

  Address* = object
    cu*: CompilationUnit
    pc*: int

  # Virtual machine and its data can be separated however it doesn't
  # bring much benefit. So we keep them together.
  ExceptionHandler* = object
    catch_pc*: int
    finally_pc*: int
    frame*: Frame
    cu*: CompilationUnit
    saved_value*: Value  # Value to restore after finally block
    has_saved_value*: bool
    in_finally*: bool

  FunctionProfile* = object
    name*: string
    call_count*: int64
    total_time*: float64  # Total time in seconds
    self_time*: float64   # Time excluding sub-calls
    min_time*: float64
    max_time*: float64

  InstructionProfile* = object
    count*: int64
    total_time*: float64  # Total time in seconds
    min_time*: float64
    max_time*: float64

  # Inline cache for symbol resolution
  InlineCache* = object
    version*: uint64      # Namespace version when cached
    value*: Value         # Cached value
    ns*: Namespace        # Namespace where value was found
    class*: Class         # Cached class for method lookup
    class_version*: uint64
    cached_method*: Method       # Cached method reference

  ThreadMetadata* = object
    id*: int
    secret*: int              # Random token for validation
    state*: ThreadState
    in_use*: bool
    parent_id*: int           # Parent thread ID
    parent_secret*: int       # Parent thread secret
    # Note: thread and channel fields will be added in vm/thread.nim module
    # which will properly import std/channels and std/locks with --threads:on

  VirtualMachine* = ref object
    cu*: CompilationUnit
    pc*: int
    frame*: Frame
    trace*: bool
    exception_handlers*: seq[ExceptionHandler]
    current_exception*: Value
    current_generator*: GeneratorObj  # Currently executing generator
    symbols*: ptr ManagedSymbols  # Pointer to global symbol table
    # Profiling
    profiling*: bool
    profile_data*: Table[string, FunctionProfile]
    profile_stack*: seq[tuple[name: string, start_time: float64]]
    # Instruction profiling
    instruction_profiling*: bool
    instruction_profile*: array[InstructionKind, InstructionProfile]
    # Async/Event Loop support
    event_loop_counter*: int  # Counter for periodic event loop polling (poll every N instructions)
    pending_futures*: seq[FutureObj]  # List of futures with pending Nim futures
    # Thread support
    thread_futures*: Table[int, FutureObj]  # Map message_id -> future for spawn_return
    message_callbacks*: seq[Value]  # List of callbacks for incoming messages
    thread_local_ns*: Namespace  # Thread-local namespace for $thread, $main_thread, etc.

  VmCallback* = proc() {.gcsafe.}

  FrameKind* {.size: sizeof(int16).} = enum
    FkPristine      # not initialized
    FrModule
    FrBody          # namespace/class/... body
    FrEval
    FkFunction
    FkMacro
    FkBlock
    FkCompileFn
    # FkNativeFn
    # FkNativeMacro
    FkNew
    FkMethod
    FkMacroMethod
    # FkNativeMethod
    # FkNativeMacroMethod
    # FkSuper
    # FkMacroSuper
    # FkBoundMethod
    # FkBoundNativeMethod

  CallBaseStack* = object
    data: seq[uint16]

  FrameObj* = object
    ref_count*: int32
    kind*: FrameKind
    caller_frame*: Frame
    caller_address*: Address
    caller_context*: Frame  # For $caller_eval in macros
    ns*: Namespace
    scope*: Scope
    target*: Value  # target of the invocation
    args*: Value
    stack*: array[256, Value]
    current_method*: Method  # Currently executing method (for super calls)
    stack_index*: uint16
    call_bases*: CallBaseStack
    from_exec_function*: bool  # Set when frame is created by exec_function
    is_generator*: bool  # Set when executing in generator context

  Frame* = ptr FrameObj

  GeneratorObj* = ref object
    function*: Function          # The generator function definition
    state*: GeneratorState       # Current execution state
    frame*: Frame                # Saved execution frame
    cu*: CompilationUnit         # Saved compilation unit
    pc*: int                     # Program counter position
    scope*: Scope                # Captured scope
    stack*: seq[Value]           # Saved stack state
    done*: bool                  # Whether generator is exhausted
    has_peeked*: bool            # Whether we have a peeked value
    peeked_value*: Value         # The peeked value from has_next

  NativeFrameKind* {.size: sizeof(int16).} = enum
    NfFunction
    NfMacro
    NfCompileFn
    NfMethod
    NfMacroMethod

  # NativeFrame is used to call native functions etc
  NativeFrame* = ref object
    kind*: NativeFrameKind
    target*: Value
    args*: Value

  # InvocationKind* {.size: sizeof(int16).} = enum
  #   IvDefault   # E.g. when the gene type is not invokable
  #   IvFunction
  #   IvMacro
  #   IvBlock
  #   IvCompileFn
  #   IvNativeFn
  #   IvNew
  #   IvMethod
  #   # IvSuper
  #   IvBoundMethod

  # Invocation* = ref object
  #   case kind*: InvocationKind
  #     of IvFunction:
  #       fn*: Value
  #       fn_scope*: Scope
  #     of IvMacro:
  #       `macro`*: Value
  #       macro_scope*: Scope
  #     of IvBlock:
  #       `block`*: Value
  #       block_scope*: Scope
  #     of IvCompileFn:
  #       compile_fn*: Value
  #       compile_fn_scope*: Scope
  #     of IvNativeFn:
  #       native_fn*: Value
  #       native_fn_args*: Value
  #     else:
  #       data: Value

  # No symbols should be removed.
  ManagedSymbols = object
    store: seq[string]
    map:  Table[string, int64]

  Exception* = object of CatchableError
    instance*: Value  # instance of Gene exception class

  NotDefinedException* = object of Exception

  # Types related to command line argument parsing
  ArgumentError* = object of Exception

  NativeFn* = proc(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.}

  # Unified Callable System
  CallableKind* = enum
    CkFunction          # Regular Gene function
    CkNativeFunction    # Nim function
    CkMethod            # Gene method
    CkNativeMethod      # Nim method
    CkBlock             # Lambda/block

  CallableFlags* = enum
    CfEvaluateArgs      # Should arguments be evaluated?
    CfNeedsSelf         # Does this callable need a self parameter?
    CfIsNative          # Is this implemented in Nim?
    CfIsMacro           # Is this a macro (unevaluated args)?
    CfIsMethod          # Is this a method (needs receiver)?
    CfCanInline         # Can this be inlined?
    CfIsPure            # Is this a pure function (no side effects)?

  Callable* = ref object
    case kind*: CallableKind
    of CkFunction, CkMethod:
      fn*: Function
    of CkNativeFunction, CkNativeMethod:
      native_fn*: NativeFn
    of CkBlock:
      block_fn*: Block

    flags*: set[CallableFlags]
    arity*: int                    # Number of required arguments
    name*: string                  # For debugging and profiling

const INST_SIZE* = sizeof(Instruction)

# NaN Boxing implementation
# We use the negative quiet NaN space (0xFFF0-0xFFFF prefix) for non-float values
# This allows all valid IEEE 754 floats to work correctly

const NAN_MASK* = 0xFFF0_0000_0000_0000u64
const PAYLOAD_MASK* = 0x0000_FFFF_FFFF_FFFFu64
const TAG_SHIFT* = 48

# Size limits for immediate integers (48-bit)
const SMALL_INT_MIN* = -(1'i64 shl 47)
const SMALL_INT_MAX* = (1'i64 shl 47) - 1

# Legacy constants for compatibility
const I64_MASK* = 0xC000_0000_0000_0000u64  # Will be removed


# Primary type tags in NaN space
# We use non-canonical quiet NaN values (0xFFF8-0xFFFF prefix with non-zero payload)
const SMALL_INT_TAG* = 0xFFF8_0000_0000_0000u64   # 48-bit integers
const POINTER_TAG* = 0xFFFC_0000_0000_0000u64     # Regular pointers
const REF_TAG* = 0xFFFD_0000_0000_0000u64         # Reference objects
const GENE_TAG* = 0xFFFA_0000_0000_0000u64        # Gene S-expressions
const SYMBOL_TAG* = 0xFFF9_0000_0000_0000u64      # Symbols
const SHORT_STR_TAG* = 0xFFFB_0000_0000_0000u64   # Short strings
const LONG_STR_TAG* = 0xFFFE_0000_0000_0000u64    # Long string pointers
const SPECIAL_TAG* = 0xFFF1_0000_0000_0000u64     # Special values (changed from 0xFFF0)

# Special values (using SPECIAL_TAG)
const NIL* = cast[Value](SPECIAL_TAG or 0)
const TRUE* = cast[Value](SPECIAL_TAG or 1)
const FALSE* = cast[Value](SPECIAL_TAG or 2)

const VOID* = cast[Value](SPECIAL_TAG or 3)
const PLACEHOLDER* = cast[Value](SPECIAL_TAG or 4)
# Used when a key does not exist in a map
const NOT_FOUND* = cast[Value](SPECIAL_TAG or 5)

# Special variable used by the parser
const PARSER_IGNORE* = cast[Value](SPECIAL_TAG or 6)

# Character encoding in special values (using SPECIAL_TAG prefix)
const CHAR_MASK = 0xFFF1_0000_0001_0000u64
const CHAR2_MASK = 0xFFF1_0000_0002_0000u64
const CHAR3_MASK = 0xFFF1_0000_0003_0000u64
const CHAR4_MASK = 0xFFF1_0000_0004_0000u64

const SHORT_STR_MASK = SHORT_STR_TAG
const LONG_STR_MASK = LONG_STR_TAG

const EMPTY_STRING = SHORT_STR_TAG

const BIGGEST_INT = 2^61 - 1

proc short_equals_long(short_raw: uint64, long_ptr: ptr String): bool {.inline, noSideEffect.} =
  ## Compare a NaN-boxed short string payload with a long string reference
  if long_ptr == nil:
    return false
  let text = long_ptr.str
  if text.len > 6:
    return false
  var payload = short_raw and PAYLOAD_MASK
  for i in 0..<text.len:
    let byte = char((payload and 0xFF'u64).int)
    if byte != text[i]:
      return false
    payload = payload shr 8
  return payload == 0

var VM* {.threadvar.}: VirtualMachine   # The current virtual machine (per-thread)

# Application is shared across all threads (initialized once by main thread)
# After initialization, it's read-only so no locking needed
var App*: Value

# Threading support
const CHANNEL_LIMIT* = 1000  # Maximum messages in channel
const MAX_THREADS* = 64      # Maximum number of threads in pool

# Thread pool is shared across all threads (protected by thread_pool_lock in vm/thread.nim)
var THREADS*: array[0..MAX_THREADS, ThreadMetadata]

var VmCreatedCallbacks*: seq[VmCallback] = @[]

# Flag to track if gene namespace has been initialized (thread-local for worker threads)
var gene_namespace_initialized* {.threadvar.}: bool

randomize()

#################### Definitions #################

proc kind*(v: Value): ValueKind {.inline.}
proc `==`*(a, b: Value): bool {.no_side_effect.}
converter to_bool*(v: Value): bool {.inline.}

proc `$`*(self: Value): string {.gcsafe.}
proc `$`*(self: ptr Reference): string
proc `$`*(self: ptr Gene): string

template gene*(v: Value): ptr Gene =
  if (cast[uint64](v) and 0xFFFF_0000_0000_0000u64) == GENE_TAG:
    cast[ptr Gene](cast[uint64](v) and PAYLOAD_MASK)
  else:
    raise newException(ValueError, "Value is not a gene")

proc new_str*(s: string): ptr String
proc new_str_value*(s: string): Value
proc str*(v: Value): string {.inline.}

converter to_value*(v: char): Value {.inline.}
converter to_value*(v: Rune): Value {.inline.}

proc get_symbol*(i: int): string {.inline.}
proc to_key*(s: string): Key {.inline.}

proc update*(self: var Scope, scope: Scope) {.inline.}

proc new_namespace*(): Namespace {.gcsafe.}
proc new_namespace*(name: string): Namespace {.gcsafe.}
proc new_namespace*(parent: Namespace): Namespace {.gcsafe.}
proc `[]=`*(self: Namespace, key: Key, val: Value) {.inline.}

#################### Common ######################

template `==`*(a, b: Key): bool =
  cast[int64](a) == cast[int64](b)

template hash*(v: Key): Hash =
  cast[Hash](v)

template `==`*(a, b: Id): bool =
  cast[int64](a) == cast[int64](b)

template hash*(v: Id): Hash =
  cast[Hash](v)

proc todo*() =
  raise new_exception(Exception, "TODO")

proc todo*(message: string) =
  raise new_exception(Exception, "TODO: " & message)

proc not_allowed*(message: string) =
  raise new_exception(Exception, message)

proc not_allowed*() =
  not_allowed("Error: should not arrive here.")

proc to_binstr*(v: int64): string =
  re.replacef(fmt"{v: 065b}", re.re"([01]{8})", "$1 ")

proc new_id*(): Id =
  cast[Id](rand(BIGGEST_INT))

# Memory pool for reference objects
var REF_POOL* {.threadvar.}: seq[ptr Reference]
const INITIAL_REF_POOL_SIZE* = 2048

# Reference counting is handled by Nim's memory management for ref types

# Value is a POD type - simple bit copy is sufficient

# Manual reference counting for Values
proc retain*(v: Value) {.inline.} =
  {.push checks: off.}
  let u = cast[uint64](v)
  if (u and NAN_MASK) == NAN_MASK:  # In NaN space
    case u and 0xFFFF_0000_0000_0000u64:
      of REF_TAG:
        let x = cast[ptr Reference](u and PAYLOAD_MASK)
        x.ref_count.inc()
      of GENE_TAG:
        let x = cast[ptr Gene](u and PAYLOAD_MASK)
        x.ref_count.inc()
      of LONG_STR_TAG:
        let x = cast[ptr String](u and PAYLOAD_MASK)
        x.ref_count.inc()
      else:
        discard  # No ref counting for other types
  {.pop.}

proc release*(v: Value) {.inline.} =
  {.push checks: off.}
  let u = cast[uint64](v)
  if (u and NAN_MASK) == NAN_MASK:  # In NaN space
    case u and 0xFFFF_0000_0000_0000u64:
      of REF_TAG:
        let x = cast[ptr Reference](u and PAYLOAD_MASK)
        if x.ref_count == 1:
          if REF_POOL.len < INITIAL_REF_POOL_SIZE * 2:
            REF_POOL.add(x)
          else:
            dealloc(x)
        else:
          x.ref_count.dec()
      of GENE_TAG:
        let x = cast[ptr Gene](u and PAYLOAD_MASK)
        if x.ref_count == 1:
          dealloc(x)
        else:
          x.ref_count.dec()
      of LONG_STR_TAG:
        let x = cast[ptr String](u and PAYLOAD_MASK)
        if x.ref_count == 1:
          dealloc(x)
        else:
          x.ref_count.dec()
      else:
        discard  # No ref counting for other types
  {.pop.}

converter to_value*(k: Key): Value {.inline.} =
  cast[Value](k)

#################### Reference ###################

# NOTE: Reference, Gene, and String are manually managed ptr types
# They use manual ref counting, not Nim's ARC/ORC
# The ref counting is handled when creating Values from these types

proc `==`*(a, b: ptr Reference): bool =
  if a.is_nil:
    return b.is_nil

  if b.is_nil:
    return false

  if a.kind != b.kind:
    return false

  case a.kind:
    of VkArray:
      return a.arr == b.arr
    of VkSet:
      return a.set == b.set
    of VkMap:
      return a.map == b.map
    of VkComplexSymbol:
      return a.csymbol == b.csymbol
    else:
      todo()

proc `$`*(self: ptr Reference): string =
  $self.kind

proc new_ref*(kind: ValueKind): ptr Reference {.inline.} =
  if REF_POOL.len > 0:
    result = REF_POOL.pop()
    result[].reset()
  else:
    result = cast[ptr Reference](alloc0(sizeof(Reference)))
  copy_mem(result, kind.addr, 2)
  result.ref_count = 1

proc `ref`*(v: Value): ptr Reference {.inline.} =
  let u = cast[uint64](v)
  if (u and 0xFFFF_0000_0000_0000u64) == REF_TAG:
    cast[ptr Reference](u and PAYLOAD_MASK)
  else:
    raise newException(ValueError, "Value is not a reference")

proc to_ref_value*(v: ptr Reference): Value {.inline.} =
  v.ref_count.inc()
  # Ensure pointer fits in 48 bits
  let ptr_addr = cast[uint64](v)
  assert (ptr_addr and 0xFFFF_0000_0000_0000u64) == 0, "Reference pointer too large for NaN boxing"
  result = cast[Value](REF_TAG or ptr_addr)

#################### Value ######################

proc `==`*(a, b: Value): bool {.no_side_effect.} =
  if cast[uint64](a) == cast[uint64](b):
    return true

  {.cast(gcsafe).}:
    let u1 = cast[uint64](a)
    let u2 = cast[uint64](b)

    # Check if both are strings (short or long) and compare them
    let tag1 = u1 and 0xFFFF_0000_0000_0000u64
    let tag2 = u2 and 0xFFFF_0000_0000_0000u64
    if tag1 != tag2:
      if tag1 == SHORT_STR_TAG and tag2 == LONG_STR_TAG:
        let str2 = cast[ptr String](u2 and PAYLOAD_MASK)
        return short_equals_long(u1, str2)
      elif tag1 == LONG_STR_TAG and tag2 == SHORT_STR_TAG:
        let str1 = cast[ptr String](u1 and PAYLOAD_MASK)
        return short_equals_long(u2, str1)
      else:
        return false

    # Both short strings
    if tag1 == SHORT_STR_TAG:
      # For short strings, if they're not bit-identical (already checked above),
      # they're not equal
      return false
    # Both long strings
    elif tag1 == LONG_STR_TAG:
      let str1 = cast[ptr String](u1 and PAYLOAD_MASK)
      let str2 = cast[ptr String](u2 and PAYLOAD_MASK)
      return str1.str == str2.str
    # Only references can be equal with different bit patterns
    elif tag1 == REF_TAG:
      return a.ref == b.ref

  # Default to false
  return false

proc is_float*(v: Value): bool {.inline, noSideEffect.} =
  let u = cast[uint64](v)
  # A value is a float if it's NOT in our NaN boxing space (0xFFF0-0xFFFF prefix)
  # The only exceptions are actual float NaN/infinity values
  if (u and NAN_MASK) != NAN_MASK:
    return true  # Regular float
  # Check for positive/negative infinity which are valid floats
  if (u and 0x7FFF_FFFF_FFFF_FFFF'u64) == 0x7FF0_0000_0000_0000'u64:
    return true  # ±infinity (0x7FF0000000000000 or 0xFFF0000000000000)
  # Everything else in NaN space is not a float
  return false

proc is_small_int*(v: Value): bool {.inline, noSideEffect.} =
  (cast[uint64](v) and 0xFFFF_0000_0000_0000u64) == SMALL_INT_TAG

# Forward declaration
converter to_int*(v: Value): int64 {.inline, noSideEffect.}

proc kind_slow(v: Value, u: uint64, tag: uint64): ValueKind {.noinline.} =
  case tag:
    of POINTER_TAG:
      return VkPointer
    of SPECIAL_TAG:
      # Special values
      case u:
        of cast[uint64](NIL):
          return VkNil
        of cast[uint64](TRUE), cast[uint64](FALSE):
          return VkBool
        of cast[uint64](VOID):
          return VkVoid
        of cast[uint64](PLACEHOLDER):
          return VkPlaceholder
        else:
          # Check for character values
          let char_type = u and 0xFFFF_FFFF_0000_0000u64
          if char_type == (CHAR_MASK and 0xFFFF_FFFF_0000_0000u64) or
             char_type == (CHAR2_MASK and 0xFFFF_FFFF_0000_0000u64) or
             char_type == (CHAR3_MASK and 0xFFFF_FFFF_0000_0000u64) or
             char_type == (CHAR4_MASK and 0xFFFF_FFFF_0000_0000u64):
            return VkChar
          else:
            todo($u)
    else:
      todo($u)

proc kind*(v: Value): ValueKind {.inline.} =
  {.cast(gcsafe).}:
    let u = cast[uint64](v)

    # Fast path: Check if it's a float first (most common case)
    if (u and NAN_MASK) != NAN_MASK:
      return VkFloat

    # Fast path: Check most common NaN-boxed types with single comparisons
    let tag = u and 0xFFFF_0000_0000_0000u64
    case tag:
      of SMALL_INT_TAG:
        return VkInt
      of REF_TAG:
        return v.ref.kind  # Single pointer dereference
      of SYMBOL_TAG:
        return VkSymbol
      of SHORT_STR_TAG, LONG_STR_TAG:
        return VkString
      of GENE_TAG:
        return VkGene
      else:
        # Uncommon cases - delegate to separate function
        return kind_slow(v, u, tag)

proc is_literal*(self: Value): bool =
  {.cast(gcsafe).}:
    let u = cast[uint64](self)

    # Floats and integers are literals
    if not ((u and NAN_MASK) == NAN_MASK):
      return true  # Regular float

    # Check NaN-boxed values
    case u and 0xFFFF_0000_0000_0000u64:
      of SMALL_INT_TAG, SHORT_STR_TAG, LONG_STR_TAG:
        result = true
      of SPECIAL_TAG:
        # nil, true, false, void, etc. are literals
        result = true
      of SYMBOL_TAG:
        result = false
      of POINTER_TAG:
        result = false
      of REF_TAG:
        let r = self.ref
        case r.kind:
          of VkArray:
            for v in r.arr:
              if not is_literal(v):
                return false
            return true
          of VkMap:
            for v in r.map.values:
              if not is_literal(v):
                return false
            return true
          of VkSelector:
            return true
          else:
            result = false
      of GENE_TAG:
        result = false
      else:
        result = false

proc str_no_quotes*(self: Value): string {.gcsafe.} =
  {.cast(gcsafe).}:
    case self.kind:
      of VkNil:
        result = "nil"
      of VkVoid:
        result = "void"
      of VkPlaceholder:
        result = "_"
      of VkBool:
        result = $(self == TRUE)
      of VkInt:
        result = $(self.to_int())
      of VkFloat:
        result = $(cast[float64](self))
      of VkChar:
        # Check if it's the special NOT_FOUND value
        if self == NOT_FOUND:
          result = "not_found"
        else:
          result = $cast[char](cast[int64](self) and 0xFF)
      of VkString:
        result = $self.str
      of VkSymbol:
        result = $self.str
      of VkComplexSymbol:
        result = self.ref.csymbol.join("/")
      of VkRatio:
        result = $self.ref.ratio_num & "/" & $self.ref.ratio_denom
      of VkArray, VkVector:
        result = "["
        for i, v in self.ref.arr:
          if i > 0:
            result &= " "
          result &= v.str_no_quotes()
        result &= "]"
      of VkSet:
        result = "#{"
        var first = true
        for v in self.ref.set:
          if not first:
            result &= " "
          result &= v.str_no_quotes()
          first = false
        result &= "}"
      of VkMap:
        result = "{"
        var first = true
        for k, v in self.ref.map:
          if not first:
            result &= " "
          # Key is a symbol value cast to int64, need to extract the symbol index
          let symbol_value = cast[Value](k)
          let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
          result &= "^" & get_symbol(symbol_index.int) & " " & v.str_no_quotes()
          first = false
        result &= "}"
      of VkSelector:
        result = "@(" & self.ref.selector_pattern & ")"
      of VkGene:
        result = $self.gene
      of VkRange:
        result = $self.ref.range_start & ".." & $self.ref.range_end
        if self.ref.range_step != NIL:
          result &= " step " & $self.ref.range_step
      of VkRegex:
        result = "/" & self.ref.regex_pattern & "/"
      of VkDate:
        result = $self.ref.date_year & "-" & $self.ref.date_month & "-" & $self.ref.date_day
      of VkDateTime:
        result = $self.ref.dt_year & "-" & $self.ref.dt_month & "-" & $self.ref.dt_day &
                 " " & $self.ref.dt_hour & ":" & $self.ref.dt_minute & ":" & $self.ref.dt_second
      of VkTime:
        result = $self.ref.time_hour & ":" & $self.ref.time_minute & ":" & $self.ref.time_second
      of VkFuture:
        result = "<Future " & $self.ref.future.state & ">"
      else:
        result = $self.kind

proc `$`*(self: Value): string {.gcsafe.} =
  {.cast(gcsafe).}:
    case self.kind:
      of VkNil:
        result = "nil"
      of VkVoid:
        result = "void"
      of VkPlaceholder:
        result = "_"
      of VkBool:
        result = $(self == TRUE)
      of VkInt:
        result = $(to_int(self))
      of VkFloat:
        result = $(cast[float64](self))
      of VkChar:
        # Check if it's the special NOT_FOUND value
        if self == NOT_FOUND:
          result = "not_found"
        else:
          result = "'" & $cast[char](cast[int64](self) and 0xFF) & "'"
      of VkString:
        result = "\"" & $self.str & "\""
      of VkSymbol:
        result = $self.str
      of VkComplexSymbol:
        result = self.ref.csymbol.join("/")
      of VkRatio:
        result = $self.ref.ratio_num & "/" & $self.ref.ratio_denom
      of VkArray, VkVector:
        result = "["
        for i, v in self.ref.arr:
          if i > 0:
            result &= " "
          result &= $v
        result &= "]"
      of VkSet:
        result = "#{"
        var first = true
        for v in self.ref.set:
          if not first:
            result &= " "
          result &= $v
          first = false
        result &= "}"
      of VkMap:
        result = "{"
        var first = true
        for k, v in self.ref.map:
          if not first:
            result &= " "
          # Key is a symbol value cast to int64, need to extract the symbol index
          let symbol_value = cast[Value](k)
          let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
          result &= "^" & get_symbol(symbol_index.int) & " " & $v
          first = false
        result &= "}"
      of VkSelector:
        result = "@(" & self.ref.selector_pattern & ")"
      of VkGene:
        result = $self.gene
      of VkRange:
        result = $self.ref.range_start & ".." & $self.ref.range_end
        if self.ref.range_step != NIL:
          result &= " step " & $self.ref.range_step
      of VkRegex:
        result = "/" & self.ref.regex_pattern & "/"
      of VkDate:
        result = $self.ref.date_year & "-" & $self.ref.date_month & "-" & $self.ref.date_day
      of VkDateTime:
        result = $self.ref.dt_year & "-" & $self.ref.dt_month & "-" & $self.ref.dt_day &
                 " " & $self.ref.dt_hour & ":" & $self.ref.dt_minute & ":" & $self.ref.dt_second
      of VkTime:
        result = $self.ref.time_hour & ":" & $self.ref.time_minute & ":" & $self.ref.time_second
      of VkFuture:
        result = "<Future " & $self.ref.future.state & ">"
      else:
        result = $self.kind

proc is_nil*(v: Value): bool {.inline.} =
  v == NIL

proc to_float*(v: Value): float64 {.inline.} =
  if is_float(v):
    return cast[float64](v)
  elif is_small_int(v):
    # Convert integer to float
    return to_int(v).float64
  else:
    raise newException(ValueError, "Value is not a number")

template float*(v: Value): float64 =
  to_float(v)

template float64*(v: Value): float64 =
  to_float(v)

converter to_value*(v: float64): Value {.inline.} =
  # In NaN boxing, floats are stored directly
  # Only NaN-boxed values (0xFFF0-0xFFFF prefix) are non-floats
  result = cast[Value](v)

converter to_bool*(v: Value): bool {.inline.} =
  not (v == FALSE or v == NIL)

converter to_value*(v: bool): Value {.inline.} =
  if v:
    return TRUE
  else:
    return FALSE

proc to_pointer*(v: Value): pointer {.inline.} =
  if (cast[uint64](v) and 0xFFFF_0000_0000_0000u64) == POINTER_TAG:
    result = cast[pointer](cast[uint64](v) and PAYLOAD_MASK)
  else:
    raise newException(ValueError, "Value is not a pointer")

converter to_value*(v: pointer): Value {.inline.} =
  if v.is_nil:
    return NIL
  else:
    # Ensure pointer fits in 48 bits (true on x86-64, ARM64)
    let ptr_addr = cast[uint64](v)
    assert (ptr_addr and 0xFFFF_0000_0000_0000u64) == 0, "Pointer too large for NaN boxing"
    result = cast[Value](POINTER_TAG or ptr_addr)

# Applicable to array, vector, string, symbol, gene etc
proc `[]`*(self: Value, i: int): Value =
  let u = cast[uint64](self)

  # Check for special values first
  if u == cast[uint64](NIL):
    return NIL

  # Check if it's in NaN space
  if (u and NAN_MASK) == NAN_MASK:
    case u and 0xFFFF_0000_0000_0000u64:
      of REF_TAG:
        let r = self.ref
        case r.kind:
          of VkArray, VkVector:
            if i >= r.arr.len:
              return NIL
            else:
              return r.arr[i]
          of VkString:
            var j = 0
            for rune in r.str.runes:
              if i == j:
                return rune
              j.inc()
            return NIL
          of VkBytes:
            if i >= r.bytes_data.len:
              return NIL
            else:
              return r.bytes_data[i].Value
          of VkRange:
            # Calculate the i-th element in the range
            let start_int = r.range_start.int64
            let step_int = if r.range_step == NIL: 1.int64 else: r.range_step.int64
            let end_int = r.range_end.int64

            let value = start_int + (i.int64 * step_int)

            # Check if the value is within the range bounds
            if step_int > 0:
              if value >= start_int and value < end_int:
                return value.Value
              else:
                return NIL
            else:  # step_int < 0
              if value <= start_int and value > end_int:
                return value.Value
              else:
                return NIL
          else:
            todo($r.kind)
      of GENE_TAG:
        let g = self.gene
        if i >= g.children.len:
          return NIL
        else:
          return g.children[i]
      of SHORT_STR_TAG, LONG_STR_TAG:
        var j = 0
        for rune in self.str().runes:
          if i == j:
            return rune
          j.inc()
        return NIL
      of SYMBOL_TAG:
        var j = 0
        for rune in self.str().runes:
          if i == j:
            return rune
          j.inc()
        return NIL
      else:
        todo($u)
  else:
    # Not in NaN space - must be a float
    todo($u)

# Applicable to array, vector, string, symbol, gene etc
proc size*(self: Value): int =
  let u = cast[uint64](self)

  # Check for special values first
  if u == cast[uint64](NIL):
    return 0

  # Check if it's in NaN space
  if (u and NAN_MASK) == NAN_MASK:
    case u and 0xFFFF_0000_0000_0000u64:
      of REF_TAG:
        let r = self.ref
        case r.kind:
          of VkArray, VkVector:
            return r.arr.len
          of VkSet:
            return r.set.len
          of VkMap:
            return r.map.len
          of VkString:
            return r.str.to_runes().len
          of VkBytes:
            return r.bytes_data.len
          of VkRange:
            # Calculate range size based on start, end, and step
            let start_int = r.range_start.int64
            let end_int = r.range_end.int64
            let step_int = if r.range_step == NIL: 1.int64 else: r.range_step.int64
            if step_int == 0:
              return 0
            elif step_int > 0:
              if start_int <= end_int:
                return int((end_int - start_int) div step_int) + 1
              else:
                return 0
            else:  # step_int < 0
              if start_int >= end_int:
                return int((start_int - end_int) div (-step_int)) + 1
              else:
                return 0
          else:
            todo($r.kind)
      of GENE_TAG:
        return self.gene.children.len
      of SHORT_STR_TAG, LONG_STR_TAG:
        return self.str().to_runes().len
      of SYMBOL_TAG:
        return self.str().to_runes().len
      else:
        return 0
  else:
    # Not in NaN space - must be a float
    return 0

#################### Int ########################

# NaN boxing for integers - supports 48-bit immediate values

converter to_value*(v: int): Value {.inline, noSideEffect.} =
  let i = v.int64
  if i >= SMALL_INT_MIN and i <= SMALL_INT_MAX:
    # Fits in 48 bits - use NaN boxing
    result = cast[Value](SMALL_INT_TAG or (cast[uint64](i) and PAYLOAD_MASK))
  else:
    # TODO: Allocate BigInt for values outside 48-bit range
    raise newException(OverflowDefect, "Integer " & $i & " outside supported range")

converter to_value*(v: int16): Value {.inline, noSideEffect.} =
  # int16 always fits in 48 bits
  result = cast[Value](SMALL_INT_TAG or (cast[uint64](v.int64) and PAYLOAD_MASK))

converter to_value*(v: int32): Value {.inline, noSideEffect.} =
  # int32 always fits in 48 bits
  result = cast[Value](SMALL_INT_TAG or (cast[uint64](v.int64) and PAYLOAD_MASK))

converter to_value*(v: int64): Value {.inline, noSideEffect.} =
  if v >= SMALL_INT_MIN and v <= SMALL_INT_MAX:
    # Fits in 48 bits - use NaN boxing
    result = cast[Value](SMALL_INT_TAG or (cast[uint64](v) and PAYLOAD_MASK))
  else:
    # TODO: Allocate BigInt for values outside 48-bit range
    raise newException(OverflowDefect, "Integer " & $v & " outside supported range")

converter to_int*(v: Value): int64 {.inline, noSideEffect.} =
  if is_small_int(v):
    # Extract and sign-extend from 48 bits
    let raw = cast[uint64](v) and PAYLOAD_MASK
    if (raw and 0x8000_0000_0000u64) != 0:
      # Negative - sign extend
      result = cast[int64](raw or 0xFFFF_0000_0000_0000u64)
    else:
      result = cast[int64](raw)
  else:
    # TODO: Handle BigInt conversion
    raise newException(ValueError, "Value is not an integer")

template int64*(v: Value): int64 =
  to_int(v)

#################### String #####################

proc new_str*(s: string): ptr String =
  result = cast[ptr String](alloc0(sizeof(String)))
  result.ref_count = 1
  result.str = s

proc new_str_value*(s: string): Value =
  let str_ptr = new_str(s)
  let ptr_addr = cast[uint64](str_ptr)
  assert (ptr_addr and 0xFFFF_0000_0000_0000u64) == 0, "String pointer too large for NaN boxing"
  result = cast[Value](LONG_STR_TAG or ptr_addr)

converter to_value*(v: char): Value {.inline.} =
  {.cast(gcsafe).}:
    # Encode char in special value space
    result = cast[Value](CHAR_MASK or v.ord.uint64)

proc str*(v: Value): string =
  {.cast(gcsafe).}:
    let u = cast[uint64](v)

    # Check if it's in NaN space
    if (u and NAN_MASK) == NAN_MASK:
      case u and 0xFFFF_0000_0000_0000u64:
        of SHORT_STR_TAG:
          let x = cast[int64](u and PAYLOAD_MASK)
          # echo x.to_binstr
          {.push checks: off}
          if x > 0xFF_FFFF:
            if x > 0xFFFF_FFFF:
              if x > 0xFF_FFFF_FFFF: # 6 chars
                result = new_string(6)
                copy_mem(result[0].addr, x.addr, 6)
              else: # 5 chars
                result = new_string(5)
                copy_mem(result[0].addr, x.addr, 5)
            else: # 4 chars
              result = new_string(4)
              copy_mem(result[0].addr, x.addr, 4)
          else:
            if x > 0xFF:
              if x > 0xFFFF: # 3 chars
                result = new_string(3)
                copy_mem(result[0].addr, x.addr, 3)
              else: # 2 chars
                result = new_string(2)
                copy_mem(result[0].addr, x.addr, 2)
            else:
              if x > 0: # 1 chars
                result = new_string(1)
                copy_mem(result[0].addr, x.addr, 1)
              else: # 0 char
                result = ""
          {.pop.}

        of LONG_STR_TAG:
          let x = cast[ptr String](u and PAYLOAD_MASK)
          result = x.str

        of SYMBOL_TAG:
          let x = cast[int64](u and PAYLOAD_MASK)
          result = get_symbol(x)

        else:
          not_allowed(fmt"{v} is not a string.")
    else:
      not_allowed(fmt"{v} is not a string.")

converter to_value*(v: string): Value =
  {.push checks: off}
  case v.len:
    of 0:
      return cast[Value](EMPTY_STRING)
    of 1:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64))
    of 2:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64, v[1].ord.shl(8).uint64))
    of 3:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64, v[1].ord.shl(8).uint64, v[2].ord.shl(16).uint64))
    of 4:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64, v[1].ord.shl(8).uint64, v[2].ord.shl(16).uint64, v[3].ord.shl(24).uint64))
    of 5:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64, v[1].ord.shl(8).uint64, v[2].ord.shl(16).uint64, v[3].ord.shl(24).uint64, v[4].ord.shl(32).uint64))
    of 6:
      return cast[Value](bitor(SHORT_STR_MASK,
        v[0].ord.uint64, v[1].ord.shl(8).uint64, v[2].ord.shl(16).uint64, v[3].ord.shl(24).uint64, v[4].ord.shl(32).uint64, v[5].ord.shl(40).uint64))
    else:
      let s = cast[ptr String](alloc0(sizeof(String)))
      s.ref_count = 1
      s.str = v
      result = cast[Value](bitor(LONG_STR_MASK, cast[uint64](s)))
  {.pop.}

converter to_value*(v: Rune): Value =
  let rune_value = v.ord.uint64
  if rune_value > 0xFF_FFFF:
    return cast[Value](bitor(CHAR4_MASK, rune_value))
  elif rune_value > 0xFFFF:
    return cast[Value](bitor(CHAR3_MASK, rune_value))
  elif rune_value > 0xFF:
    return cast[Value](bitor(CHAR2_MASK, rune_value))
  else:
    return cast[Value](bitor(CHAR_MASK, rune_value))

#################### Symbol #####################

var SYMBOLS*: ManagedSymbols

proc get_symbol*(i: int): string {.inline.} =
  SYMBOLS.store[i]

proc get_symbol_gcsafe*(i: int): string {.inline, gcsafe.} =
  {.cast(gcsafe).}:
    result = SYMBOLS.store[i]

proc to_symbol_value*(s: string): Value =
  {.cast(gcsafe).}:
    let found = SYMBOLS.map.get_or_default(s, -1)
    if found != -1:
      let i = found.uint64
      result = cast[Value](SYMBOL_TAG or i)
    else:
      let new_id = SYMBOLS.store.len.uint64
      # Ensure symbol ID fits in 48 bits
      assert new_id <= PAYLOAD_MASK, "Too many symbols for NaN boxing"
      result = cast[Value](SYMBOL_TAG or new_id)
      SYMBOLS.map[s] = SYMBOLS.store.len
      SYMBOLS.store.add(s)

proc to_key*(s: string): Key {.inline.} =
  cast[Key](to_symbol_value(s))

#################### ComplexSymbol ###############

proc to_complex_symbol*(parts: seq[string]): Value {.inline.} =
  let r = new_ref(VkComplexSymbol)
  r.csymbol = parts
  result = r.to_ref_value()

#################### Array #######################

proc new_array_value*(v: varargs[Value]): Value =
  let r = new_ref(VkArray)
  r.arr = @v
  result = r.to_ref_value()

proc len*(self: Value): int =
  case self.kind
  of VkString:
    return self.str.len
  of VkArray, VkVector:
    return self.ref.arr.len
  of VkMap:
    return self.ref.map.len
  of VkSet:
    return self.ref.set.len
  of VkGene:
    return self.gene.children.len
  of VkRange:
    # Calculate range length: (end - start) / step + 1
    let start = self.ref.range_start.int
    let endVal = self.ref.range_end.int
    let step = if self.ref.range_step == NIL: 1 else: self.ref.range_step.int
    if step == 0:
      return 0
    return ((endVal - start) div step) + 1
  else:
    return 0

#################### Stream ######################

proc new_stream_value*(v: varargs[Value]): Value =
  let r = new_ref(VkStream)
  r.stream = @v
  result = r.to_ref_value()

#################### Set #########################

proc new_set_value*(): Value =
  let r = new_ref(VkSet)
  result = r.to_ref_value()

#################### Map #########################

proc new_map_value*(): Value =
  let r = new_ref(VkMap)
  result = r.to_ref_value()

proc new_map_value*(map: Table[Key, Value]): Value =
  let r = new_ref(VkMap)
  r.map = map
  result = r.to_ref_value()

#################### Range ######################

proc new_range_value*(start: Value, `end`: Value, step: Value): Value =
  let r = new_ref(VkRange)
  r.range_start = start
  r.range_end = `end`
  r.range_step = step
  result = r.to_ref_value()

proc new_regex_value*(pattern: string, flags: uint8 = 0'u8): Value =
  let r = new_ref(VkRegex)
  r.regex_pattern = pattern
  r.regex_flags = flags
  result = r.to_ref_value()

proc new_date_value*(year: int, month: int, day: int): Value =
  let r = new_ref(VkDate)
  r.date_year = year.int16
  r.date_month = month.int8
  r.date_day = day.int8
  result = r.to_ref_value()

proc new_datetime_value*(dt: DateTime): Value =
  let r = new_ref(VkDateTime)
  r.dt_year = dt.year.int16
  r.dt_month = ord(dt.month).int8
  r.dt_day = dt.monthday.int8
  r.dt_hour = dt.hour.int8
  r.dt_minute = dt.minute.int8
  r.dt_second = dt.second.int8
  r.dt_timezone = (dt.utcOffset div 60).int16
  result = r.to_ref_value()

proc new_time_value*(hour: int, minute: int, second: int, microsecond: int = 0): Value =
  let r = new_ref(VkTime)
  r.time_hour = hour.int8
  r.time_minute = minute.int8
  r.time_second = second.int8
  r.time_microsecond = microsecond.int32
  result = r.to_ref_value()

proc new_selector_value*(segments: openArray[Value]): Value =
  if segments.len == 0:
    not_allowed("Selector requires at least one segment")

  let r = new_ref(VkSelector)
  r.selector_path = @[]

  var pattern_parts: seq[string] = @[]
  for seg in segments:
    case seg.kind:
      of VkString, VkSymbol:
        pattern_parts.add(seg.str)
        r.selector_path.add(seg)
      of VkInt:
        pattern_parts.add($seg.int64)
        r.selector_path.add(seg)
      else:
        not_allowed("Invalid selector segment: " & $seg.kind)

  r.selector_pattern = pattern_parts.join("/")
  result = r.to_ref_value()

#################### SourceTrace ##################

proc new_source_trace*(filename: string, line, column: int): SourceTrace =
  SourceTrace(
    filename: filename,
    line: line,
    column: column,
    children: @[],
    child_index: -1,
  )

proc attach_child*(parent: SourceTrace, child: SourceTrace) =
  if parent.is_nil or child.is_nil:
    return
  child.parent = parent
  child.child_index = parent.children.len
  parent.children.add(child)

proc trace_location*(trace: SourceTrace): string =
  if trace.is_nil:
    return ""
  if trace.filename.len > 0:
    result = trace.filename & ":" & $trace.line & ":" & $trace.column
  else:
    result = $trace.line & ":" & $trace.column

#################### Gene ########################

proc to_gene_value*(v: ptr Gene): Value {.inline.} =
  v.ref_count.inc()
  # Ensure pointer fits in 48 bits
  let ptr_addr = cast[uint64](v)
  assert (ptr_addr and 0xFFFF_0000_0000_0000u64) == 0, "Gene pointer too large for NaN boxing"
  result = cast[Value](GENE_TAG or ptr_addr)

proc `$`*(self: ptr Gene): string =
  result = "(" & $self.type
  for k, v in self.props:
    result &= " ^" & get_symbol(k.int64) & " " & $v
  for child in self.children:
    result &= " " & $child
  result &= ")"

proc new_gene*(): ptr Gene =
  result = cast[ptr Gene](alloc0(sizeof(Gene)))
  result.ref_count = 1
  result.type = NIL
  result.trace = nil
  result.props = Table[Key, Value]()
  result.children = @[]

proc new_gene*(`type`: Value): ptr Gene =
  result = cast[ptr Gene](alloc0(sizeof(Gene)))
  result.ref_count = 1
  result.type = `type`
  result.trace = nil
  result.props = Table[Key, Value]()
  result.children = @[]

proc new_gene_value*(): Value {.inline.} =
  new_gene().to_gene_value()

proc new_gene_value*(`type`: Value): Value {.inline.} =
  new_gene(`type`).to_gene_value()

# proc args_are_literal(self: ptr Gene): bool =
#   for k, v in self.props:
#     if not v.is_literal():
#       return false
#   for v in self.children:
#     if not v.is_literal():
#       return false
#   true

#################### Application #################

proc refresh_env_map*()
proc set_program_args*(program: string, args: seq[string])

proc app*(self: Value): Application {.inline.} =
  self.ref.app

proc new_app*(): Application =
  result = Application()
  let global = new_namespace("global")
  result.ns = global

#################### Namespace ###################

proc ns*(self: Value): Namespace {.inline.} =
  self.ref.ns

proc to_value*(self: Namespace): Value {.inline.} =
  let r = new_ref(VkNamespace)
  r.ns = self
  result = r.to_ref_value()

proc new_namespace*(): Namespace =
  return Namespace(
    name: "<root>",
    members: Table[Key, Value](),
  )

proc new_namespace*(parent: Namespace): Namespace =
  return Namespace(
    parent: parent,
    name: "<root>",
    members: Table[Key, Value](),
  )

proc new_namespace*(name: string): Namespace =
  return Namespace(
    name: name,
    members: Table[Key, Value](),
  )

proc new_namespace*(parent: Namespace, name: string): Namespace =
  return Namespace(
    parent: parent,
    name: name,
    members: Table[Key, Value](),
  )

proc root*(self: Namespace): Namespace =
  if self.name == "<root>":
    return self
  else:
    return self.parent.root

proc get_module*(self: Namespace): Module =
  if self.module == nil:
    if self.parent != nil:
      return self.parent.get_module()
    else:
      return
  else:
    return self.module

proc package*(self: Namespace): Package =
  self.get_module().pkg

proc has_key*(self: Namespace, key: Key): bool {.inline.} =
  return self.members.has_key(key) or (self.parent != nil and self.parent.has_key(key))

proc `[]`*(self: Namespace, key: Key): Value =
  let found = self.members.get_or_default(key, NOT_FOUND)
  if found != NOT_FOUND:
    return found
  elif not self.stop_inheritance and self.parent != nil:
    return self.parent[key]
  else:
    return NIL
    # return NOT_FOUND
    # raise new_exception(NotDefinedException, get_symbol(key.int64) & " is not defined")

proc locate*(self: Namespace, key: Key): (Value, Namespace) =
  let found = self.members.get_or_default(key, NOT_FOUND)
  if found != NOT_FOUND:
    result = (found, self)
  elif not self.stop_inheritance and self.parent != nil:
    result = self.parent.locate(key)
  else:
    not_allowed()

proc `[]=`*(self: Namespace, key: Key, val: Value) {.inline.} =
  self.members[key] = val
  self.version.inc()  # Invalidate caches on mutation

proc get_members*(self: Namespace): Value =
  todo()
  # result = new_gene_map()
  # for k, v in self.members:
  #   result.map[k] = v

proc member_names*(self: Namespace): Value =
  todo()
  # result = new_gene_vec()
  # for k, _ in self.members:
  #   result.vec.add(k)

# proc on_member_missing*(frame: Frame, self: Value, args: Value): Value =
proc on_member_missing*(vm_data: VirtualMachine, args: Value): Value =
  todo()
  # let self = args.gene_type
  # case self.kind
  # of VkNamespace:
  #   self.ns.on_member_missing.add(args.gene_children[0])
  # of VkClass:
  #   self.class.ns.on_member_missing.add(args.gene_children[0])
  # of VkMixin:
  #   self.mixin.ns.on_member_missing.add(args.gene_children[0])
  # else:
  #   todo("member_missing " & $self.kind)

#################### Scope #######################



proc free*(self: Scope) =
  {.push checks: off, optimization: speed.}
  self.ref_count.dec()
  if self.ref_count == 0:
    if self.parent != nil:
      # When this scope is destroyed, release the reference to parent
      self.parent.free()  # This will decrement parent's ref_count and free if needed
    dealloc(self)
  {.pop.}

proc update*(self: var Scope, scope: Scope) {.inline.} =
  {.push checks: off, optimization: speed.}
  if scope != nil:
    scope.ref_count.inc()
  if self != nil:
    self.free()
  self = scope
  {.pop.}

proc new_scope*(tracker: ScopeTracker): Scope =
  result = cast[Scope](alloc0(sizeof(ScopeObj)))
  result.ref_count = 1
  result.tracker = tracker
  result.members = newSeq[Value]()  # Initialize members sequence explicitly
  result.parent = nil  # Explicitly initialize parent

proc max*(self: Scope): int16 {.inline.} =
  return self.members.len.int16

proc set_parent*(self: Scope, parent: Scope) {.inline.} =
  parent.ref_count.inc()
  self.parent = parent

proc new_scope*(tracker: ScopeTracker, parent: Scope): Scope =
  result = new_scope(tracker)
  if not parent.is_nil():
    result.set_parent(parent)

proc locate(self: ScopeTracker, key: Key, max: int): VarIndex =
  let found = self.mappings.get_or_default(key, -1)
  if found >= 0 and found < max:
    return VarIndex(parent_index: 0, local_index: found)
  elif self.parent.is_nil():
    return VarIndex(parent_index: 0, local_index: -1)
  else:
    result = self.parent.locate(key, self.parent_index_max.int)
    if self.next_index > 0: # if current scope is not empty
      result.parent_index.inc()

proc locate*(self: ScopeTracker, key: Key): VarIndex =
  let found = self.mappings.get_or_default(key, -1)
  if found >= 0:
    return VarIndex(parent_index: 0, local_index: found)
  elif self.parent.is_nil():
    return VarIndex(parent_index: 0, local_index: -1)
  else:
    result = self.parent.locate(key, self.parent_index_max.int)
    # Only increment parent_index if we actually created a runtime scope
    # (indicated by scope_started flag or having variables)
    if self.next_index > 0 or self.scope_started:
      result.parent_index.inc()

#################### ScopeTracker ################

proc new_scope_tracker*(): ScopeTracker =
  ScopeTracker()

proc new_scope_tracker*(parent: ScopeTracker): ScopeTracker =
  result = ScopeTracker()
  var p = parent
  while p != nil:
    if p.next_index > 0:
      result.parent = p
      result.parent_index_max = p.next_index
      return
    p = p.parent

proc copy_scope_tracker*(source: ScopeTracker): ScopeTracker =
  result = ScopeTracker()
  result.next_index = source.next_index
  result.parent_index_max = source.parent_index_max
  result.parent = source.parent
  # Copy the mappings table
  for key, value in source.mappings:
    result.mappings[key] = value

proc add*(self: var ScopeTracker, name: Key) =
  self.mappings[name] = self.next_index
  self.next_index.inc()

proc snapshot_scope_tracker*(tracker: ScopeTracker): ScopeTrackerSnapshot =
  if tracker == nil:
    return nil

  result = ScopeTrackerSnapshot(
    next_index: tracker.next_index,
    parent_index_max: tracker.parent_index_max,
    scope_started: tracker.scope_started,
    mappings: @[],
    parent: snapshot_scope_tracker(tracker.parent)
  )

  for key, value in tracker.mappings:
    result.mappings.add((key, value))

proc materialize_scope_tracker*(snapshot: ScopeTrackerSnapshot): ScopeTracker =
  if snapshot == nil:
    return nil

  result = ScopeTracker(
    next_index: snapshot.next_index,
    parent_index_max: snapshot.parent_index_max,
    scope_started: snapshot.scope_started,
    parent: materialize_scope_tracker(snapshot.parent)
  )

  for pair in snapshot.mappings:
    result.mappings[pair[0]] = pair[1]

proc new_function_def_info*(tracker: ScopeTracker, body: CompilationUnit = nil): FunctionDefInfo =
  var body_value = NIL
  if body != nil:
    let cu_ref = new_ref(VkCompiledUnit)
    cu_ref.cu = body
    body_value = cu_ref.to_ref_value()

  result = FunctionDefInfo(
    scope_tracker: tracker,
    compiled_body: body_value
  )

proc to_value*(info: FunctionDefInfo): Value =
  let r = new_ref(VkFunctionDef)
  r.function_def = info
  result = r.to_ref_value()

proc to_function_def_info*(value: Value): FunctionDefInfo =
  if value.kind != VkFunctionDef:
    not_allowed("Expected FunctionDef info value")
  result = value.ref.function_def

#################### Pattern Matching ############

proc new_match_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchExpression,
  )

proc new_arg_matcher*(): RootMatcher =
  result = RootMatcher(
    mode: MatchArguments,
  )

proc new_matcher*(root: RootMatcher, kind: MatcherKind): Matcher =
  result = Matcher(
    root: root,
    kind: kind,
  )

proc is_empty*(self: RootMatcher): bool =
  self.children.len == 0

proc required*(self: Matcher): bool =
  # return self.default_value_expr == nil and not self.is_splat
  return not self.is_splat

proc check_hint*(self: RootMatcher) =
  if self.children.len == 0:
    self.hint_mode = MhNone
  else:
    self.hint_mode = MhSimpleData
    for item in self.children:
      if item.kind != MatchData or not item.required:
        self.hint_mode = MhDefault
        return

# proc hint*(self: RootMatcher): MatchingHint =
#   if self.children.len == 0:
#     result.mode = MhNone
#   else:
#     result.mode = MhSimpleData
#     for item in self.children:
#       if item.kind != MatchData or not item.required:
#         result.mode = MhDefault
#         return

# proc new_matched_field*(name: string, value: Value): MatchedField =
#   result = MatchedField(
#     name: name,
#     value: value,
#   )

proc props*(self: seq[Matcher]): HashSet[Key] =
  for m in self:
    if m.kind == MatchProp and not m.is_splat:
      result.incl(m.name_key)

proc prop_splat*(self: seq[Matcher]): Key =
  for m in self:
    if m.kind == MatchProp and m.is_splat:
      return m.name_key

proc parse*(self: RootMatcher, v: Value)

proc calc_next*(self: Matcher) =
  var last: Matcher = nil
  for m in self.children.mitems:
    m.calc_next()
    if m.kind in @[MatchData, MatchLiteral]:
      if last != nil:
        last.next = m
      last = m

proc calc_next*(self: RootMatcher) =
  var last: Matcher = nil
  for m in self.children.mitems:
    m.calc_next()
    if m.kind in @[MatchData, MatchLiteral]:
      if last != nil:
        last.next = m
      last = m

proc calc_min_left*(self: Matcher) =
  {.push checks: off}
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    let m = self.children[i]
    m.calc_min_left()
    m.min_left = min_left
    if m.required:
      min_left += 1
  {.pop.}

proc calc_min_left*(self: RootMatcher) =
  {.push checks: off}
  var min_left = 0
  var i = self.children.len
  while i > 0:
    i -= 1
    let m = self.children[i]
    m.calc_min_left()
    m.min_left = min_left
    if m.required:
      min_left += 1
  {.pop.}

proc parse(self: RootMatcher, group: var seq[Matcher], v: Value) =
  {.push checks: off}
  case v.kind:
    of VkSymbol:
      if v.str[0] == '^':
        let m = new_matcher(self, MatchProp)
        if v.str.ends_with("..."):
          m.is_splat = true
          if v.str[1] == '^':
            m.name_key = v.str[2..^4].to_key()
            m.is_prop = true
          else:
            m.name_key = v.str[1..^4].to_key()
            m.is_prop = true  # Named parameters always have is_prop = true
        else:
          if v.str[1] == '^':
            m.name_key = v.str[2..^1].to_key()
            m.is_prop = true
          else:
            m.name_key = v.str[1..^1].to_key()
            m.is_prop = true  # Named parameters always have is_prop = true
        group.add(m)
      else:
        let m = new_matcher(self, MatchData)
        group.add(m)
        if v.str != "_":
          if v.str.ends_with("..."):
            m.is_splat = true
            if v.str[0] == '^':
              m.name_key = v.str[1..^4].to_key()
              m.is_prop = true
            else:
              m.name_key = v.str[0..^4].to_key()
          else:
            if v.str[0] == '^':
              m.name_key = v.str[1..^1].to_key()
              m.is_prop = true
            else:
              m.name_key = v.str.to_key()
    of VkComplexSymbol:
      if v.ref.csymbol[0] == "^":
        todo("parse " & $v)
      else:
        var m = new_matcher(self, MatchData)
        group.add(m)
        m.is_prop = true
        let name = v.ref.csymbol[1]
        if name.ends_with("..."):
          m.is_splat = true
          m.name_key = name[0..^4].to_key()
        else:
          m.name_key = name.to_key()
    of VkArray:
      var i = 0
      while i < v.ref.arr.len:
        let item = v.ref.arr[i]
        i += 1
        if item.kind == VkArray:
          let m = new_matcher(self, MatchData)
          group.add(m)
          self.parse(m.children, item)
        else:
          self.parse(group, item)
          if i < v.ref.arr.len and v.ref.arr[i] == "=".to_symbol_value():
            i += 1
            let last_matcher = group[^1]
            let value = v.ref.arr[i]
            i += 1
            last_matcher.default_value = value
    of VkQuote:
      todo($VkQuote)
      # var m = new_matcher(self, MatchLiteral)
      # m.literal = v.quote
      # m.name = "<literal>"
      # group.add(m)
    else:
      todo("parse " & $v.kind)
  {.pop.}

proc parse*(self: RootMatcher, v: Value) =
  if v == nil or v == to_symbol_value("_"):
    return
  self.parse(self.children, v)
  self.calc_min_left()
  self.calc_next()

proc new_arg_matcher*(value: Value): RootMatcher =
  result = new_arg_matcher()
  result.parse(value)
  result.check_hint()

#################### Function ####################

proc new_fn*(name: string, matcher: RootMatcher, body: sink seq[Value]): Function =
  return Function(
    name: name,
    matcher: matcher,
    # matching_hint: matcher.hint,
    body: body,
  )

proc to_function*(node: Value): Function {.gcsafe.} =
  if node.kind != VkGene:
    raise new_exception(Exception, "Expected Gene for function definition, got " & $node.kind)

  if node.gene == nil:
    raise new_exception(Exception, "Gene pointer is nil")

  var name: string
  let matcher = new_arg_matcher()
  var body_start: int
  var is_generator = false
  var is_macro_like = false

  # Check if defined with fn! type
  if node.gene.type != NIL and node.gene.type == "fn!".to_symbol_value():
    is_macro_like = true

  if node.gene.type != NIL and node.gene.type == "fnx".to_symbol_value():
    matcher.parse(node.gene.children[0])
    name = "<unnamed>"
    body_start = 1
  elif node.gene.type != NIL and node.gene.type == "fnxx".to_symbol_value():
    name = "<unnamed>"
    body_start = 0
  else:
    if node.gene.children.len == 0:
      raise new_exception(Exception, "Invalid function definition: expected function name")
    let first = node.gene.children[0]
    case first.kind:
      of VkSymbol, VkString:
        name = first.str
        # Check if function name ends with ! (macro-like function)
        if name.len > 0 and name[^1] == '!':
          is_macro_like = true
        # Check if function name ends with * (generator function)
        elif name.len > 0 and name[^1] == '*':
          is_generator = true
      of VkComplexSymbol:
        name = first.ref.csymbol[^1]
        # Check if function name ends with ! (macro-like function)
        if name.len > 0 and name[^1] == '!':
          is_macro_like = true
        # Check if function name ends with * (generator function)
        elif name.len > 0 and name[^1] == '*':
          is_generator = true
      else:
        todo($first.kind)

    matcher.parse(node.gene.children[1])
    body_start = 2

  matcher.check_hint()
  var body: seq[Value] = @[]
  for i in body_start..<node.gene.children.len:
    body.add node.gene.children[i]

  # Check if function has async attribute from properties
  var is_async = false
  let async_key = "async".to_key()
  if node.gene.props.has_key(async_key) and node.gene.props[async_key] == TRUE:
    is_async = true
    discard  # Function is async

  # Check if function has generator flag from properties (^^generator syntax)
  let generator_key = "generator".to_key()
  if node.gene.props.has_key(generator_key) and node.gene.props[generator_key] == TRUE:
    is_generator = true

  # body = wrap_with_try(body)
  result = new_fn(name, matcher, body)
  result.async = is_async
  result.is_generator = is_generator
  result.is_macro_like = is_macro_like

# compile method is defined in compiler.nim

#################### CompileFn ###################

proc new_compile_fn*(name: string, matcher: RootMatcher, body: sink seq[Value]): CompileFn =
  return CompileFn(
    name: name,
    matcher: matcher,
    # matching_hint: matcher.hint,
    body: body,
  )

proc to_compile_fn*(node: Value): CompileFn {.gcsafe.} =
  let first = node.gene.children[0]
  var name: string
  if first.kind == VkSymbol:
    name = first.str
  elif first.kind == VkComplexSymbol:
    name = first.ref.csymbol[^1]

  let matcher = new_arg_matcher()
  matcher.parse(node.gene.children[1])
  matcher.check_hint()

  var body: seq[Value] = @[]
  for i in 2..<node.gene.children.len:
    body.add node.gene.children[i]

  # body = wrap_with_try(body)
  result = new_compile_fn(name, matcher, body)

# compile method needs to be defined - see compiler.nim

#################### Block #######################

proc new_block*(matcher: RootMatcher,  body: sink seq[Value]): Block =
  return Block(
    matcher: matcher,
    # matching_hint: matcher.hint,
    body: body,
  )

proc to_block*(node: Value): Block {.gcsafe.} =
  let matcher = new_arg_matcher()
  var body_start: int
  if node.gene.type == "->".to_symbol_value():
    body_start = 0
  else:
    matcher.parse(node.gene.type)
    body_start = 1

  matcher.check_hint()
  var body: seq[Value] = @[]
  for i in body_start..<node.gene.children.len:
    body.add node.gene.children[i]

  # body = wrap_with_try(body)
  result = new_block(matcher, body)

# compile method needs to be defined - see compiler.nim

#################### Class #######################

proc new_class*(name: string, parent: Class): Class =
  result = Class(
    name: name,
    ns: new_namespace(nil, name),
    parent: parent,
    constructor: NIL,
    members: initTable[Key, Value](),
    methods: initTable[Key, Method](),
    version: 0,
    has_macro_constructor: false,  # Initialize to false, will be set during constructor compilation
  )

proc new_class*(name: string): Class =
  var parent: Class
  # if VM.object_class != nil:
  #   parent = VM.object_class.class
  new_class(name, parent)

proc get_constructor*(self: Class): Value =
  if self.constructor.is_nil:
    if not self.parent.is_nil:
      return self.parent.get_constructor()
  else:
    return self.constructor

proc has_method*(self: Class, name: Key): bool =
  if self.methods.has_key(name):
    return true
  elif self.parent != nil:
    return self.parent.has_method(name)

proc has_method*(self: Class, name: string): bool {.inline.} =
  self.has_method(name.to_key)

proc get_method*(self: Class, name: Key): Method =
  let found = self.methods.get_or_default(name, nil)
  if not found.is_nil:
    return found
  elif self.parent != nil:
    return self.parent.get_method(name)
  # else:
  #   not_allowed("No method available: " & name.to_s)

proc get_method*(self: Class, name: string): Method {.inline.} =
  self.get_method(name.to_key)

proc get_super_method*(self: Class, name: string): Method =
  if self.parent != nil:
    return self.parent.get_method(name)
  else:
    not_allowed("No super method available: " & name)

proc get_class*(val: Value): Class =
  case val.kind:
    of VkApplication:
      return App.ref.app.application_class.ref.class
    of VkPackage:
      return App.ref.app.package_class.ref.class
    of VkInstance:
      return val.ref.instance_class
    of VkCustom:
      if val.ref.custom_class != nil:
        return val.ref.custom_class
      else:
        return App.ref.app.object_class.ref.class
    # of VkCast:
    #   return val.cast_class
    of VkClass:
      return App.ref.app.class_class.ref.class
    # of VkMixin:
    #   return App.ref.app.mixin_class.ref.class
    of VkNamespace:
      return App.ref.app.namespace_class.ref.class
    of VkFuture:
      if App.ref.app.future_class.kind == VkClass:
        return App.ref.app.future_class.ref.class
      else:
        return nil
    of VkGenerator:
      if App.ref.app.generator_class.kind == VkClass:
        return App.ref.app.generator_class.ref.class
      else:
        return nil
    # of VkThread:
    #   return App.ref.app.thread_class.ref.class
    # of VkThreadMessage:
    #   return App.ref.app.thread_message_class.ref.class
    # of VkNativeFile:
    #   return App.ref.app.file_class.ref.class
    # of VkException:
    #   let ex = val.exception
    #   if ex is ref Exception:
    #     let ex = cast[ref Exception](ex)
    #     if ex.instance != nil:
    #       return ex.instance.instance_class
    #     else:
    #       return App.ref.app.exception_class.ref.class
    #   else:
    #     return App.ref.app.exception_class.ref.class
    of VkNil:
      return App.ref.app.nil_class.ref.class
    of VkBool:
      return App.ref.app.bool_class.ref.class
    of VkInt:
      return App.ref.app.int_class.ref.class
    of VkFloat:
      return App.ref.app.float_class.ref.class
    of VkChar:
      return App.ref.app.char_class.ref.class
    of VkString:
      return App.ref.app.string_class.ref.class
    of VkSymbol:
      return App.ref.app.symbol_class.ref.class
    of VkComplexSymbol:
      return App.ref.app.complex_symbol_class.ref.class
    of VkArray:
      return App.ref.app.array_class.ref.class
    of VkMap:
      return App.ref.app.map_class.ref.class
    of VkSet:
      return App.ref.app.set_class.ref.class
    of VkGene:
      return App.ref.app.gene_class.ref.class
    # of VkRegex:
    #   return App.ref.app.regex_class.ref.class
    # of VkRange:
    #   return App.ref.app.range_class.ref.class
    # of VkDate:
    #   return App.ref.app.date_class.ref.class
    # of VkDateTime:
    #   return App.ref.app.datetime_class.ref.class
    # of VkTime:
    #   return App.ref.app.time_class.ref.class
    of VkFunction:
      return App.ref.app.function_class.ref.class
    # of VkTimezone:
    #   return App.ref.app.timezone_class.ref.class
    # of VkAny:
    #   if val.any_class == nil:
    #     return App.ref.app.object_class.ref.class
    #   else:
    #     return val.any_class
    # of VkCustom:
    #   if val.custom_class == nil:
    #     return App.ref.app.object_class.ref.class
    #   else:
    #     return val.custom_class
    else:
      todo("get_class " & $val.kind)

proc has_object_class*(val: Value): bool {.inline.} =
  case val.kind
  of VkInstance, VkCustom:
    true
  else:
    false

proc get_object_class*(val: Value): Class {.inline.} =
  case val.kind
  of VkInstance:
    val.ref.instance_class
  of VkCustom:
    val.ref.custom_class
  else:
    nil

proc require_object_class*(val: Value, context: string): Class =
  let cls = val.get_object_class()
  if cls.is_nil:
    raise new_exception(Exception, context)
  cls

proc new_custom_value*(custom_class: Class, data: CustomValue): Value =
  ## Create a VkCustom value backed by a Gene class.
  if custom_class.is_nil:
    raise new_exception(Exception, "Custom values require a class")
  let ref_val = new_ref(VkCustom)
  ref_val.custom_class = custom_class
  ref_val.custom_data = data
  ref_val.to_ref_value()

proc get_custom_data*(val: Value, context: string = "Custom value expected"): CustomValue =
  ## Retrieve the CustomValue payload from a VkCustom value.
  if val.kind != VkCustom:
    raise new_exception(Exception, context)
  if val.ref.custom_data.is_nil:
    raise new_exception(Exception, context & ": missing payload")
  val.ref.custom_data

proc object_class_name*(val: Value): string =
  let cls = val.get_object_class()
  if cls.is_nil or cls.name.len == 0:
    return "UnknownObject"
  cls.name

proc is_a*(self: Value, class: Class): bool =
  var my_class = self.get_class
  while true:
    if my_class == class:
      return true
    if my_class.parent == nil:
      return false
    else:
      my_class = my_class.parent

proc def_native_method*(self: Class, name: string, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.methods[name.to_key()] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
  )
  self.version.inc()

proc def_member*(self: Class, name: string, value: Value) =
  self.members[name.to_key()] = value
  self.version.inc()

proc def_static_method*(self: Class, name: string, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.members[name.to_key()] = r.to_ref_value()
  self.version.inc()

proc get_member*(self: Class, name: Key): Value =
  if self.members.hasKey(name):
    return self.members[name]
  if not self.parent.is_nil:
    return self.parent.get_member(name)
  return NIL

proc def_native_constructor*(self: Class, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.constructor = r.to_ref_value()

# proc def_native_method*(self: Class, name: string, f: NativeFn2) =
#   let r = new_ref(VkNativeFn2)
#   r.native_fn2 = f
#   self.methods[name.to_key()] = Method(
#     class: self,
#     name: name,
#     callable: r.to_ref_value(),
#   )

proc def_native_macro_method*(self: Class, name: string, f: NativeFn) =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  self.methods[name.to_key()] = Method(
    class: self,
    name: name,
    callable: r.to_ref_value(),
    is_macro: true,
  )
  self.version.inc()

proc add_standard_instance_methods*(class: Class) =
  # Currently no standard methods to add
  discard

# proc def_native_constructor*(self: Class, f: NativeFn2) =
#   let r = new_ref(VkNativeFn2)
#   r.native_fn2 = f
#   self.constructor = r.to_ref_value()

#################### Method ######################

proc new_method*(class: Class, name: string, fn: Function): Method =
  let r = new_ref(VkFunction)
  r.fn = fn
  return Method(
    class: class,
    name: name,
    callable: r.to_ref_value(),
  )

proc clone*(self: Method): Method =
  return Method(
    class: self.class,
    name: self.name,
    callable: self.callable,
  )

#################### Callable ######################

proc new_callable*(kind: CallableKind, name: string = ""): Callable =
  result = Callable(kind: kind, name: name, arity: 0, flags: {})

  # Set default flags based on kind
  case kind:
  of CkFunction:
    result.flags = {CfEvaluateArgs}
  of CkNativeFunction:
    result.flags = {CfEvaluateArgs, CfIsNative}
  of CkMethod:
    result.flags = {CfEvaluateArgs, CfIsMethod, CfNeedsSelf}
  of CkNativeMethod:
    result.flags = {CfEvaluateArgs, CfIsMethod, CfNeedsSelf, CfIsNative}
  of CkBlock:
    result.flags = {CfEvaluateArgs}

proc get_arity*(matcher: RootMatcher): int =
  # Calculate minimum required arguments
  result = 0
  for child in matcher.children:
    if child.required:
      result.inc()

proc to_callable*(fn: Function): Callable =
  result = new_callable(CkFunction, fn.name)
  result.fn = fn
  result.arity = fn.matcher.get_arity()

proc to_callable*(native_fn: NativeFn, name: string = "", arity: int = 0): Callable =
  result = new_callable(CkNativeFunction, name)
  result.native_fn = native_fn
  result.arity = arity

proc to_callable*(blk: Block): Callable =
  result = new_callable(CkBlock)
  result.block_fn = blk
  result.arity = blk.matcher.get_arity()

proc to_callable*(value: Value): Callable =
  case value.kind:
  of VkFunction:
    return value.ref.fn.to_callable()
  of VkNativeFn:
    return to_callable(value.ref.native_fn)
  of VkBlock:
    return value.ref.block.to_callable()
  else:
    not_allowed("Cannot convert " & $value.kind & " to Callable")

#################### Future ######################

proc new_future*(): FutureObj =
  result = FutureObj(
    state: FsPending,
    value: NIL,
    success_callbacks: @[],
    failure_callbacks: @[],
    nim_future: nil  # Synchronous future by default
  )

proc new_future*(nim_fut: Future[Value]): FutureObj =
  ## Create a FutureObj that wraps a Nim async future
  result = FutureObj(
    state: FsPending,
    value: NIL,
    success_callbacks: @[],
    failure_callbacks: @[],
    nim_future: nim_fut
  )

proc new_future_value*(): Value =
  let r = new_ref(VkFuture)
  r.future = new_future()
  return r.to_ref_value()

proc complete*(f: FutureObj, value: Value) =
  if f.state != FsPending:
    not_allowed("Future already completed")
  f.state = FsSuccess
  f.value = value
  # Execute success callbacks
  # Note: Callbacks are executed immediately when future completes
  # In real async, these would be scheduled on the event loop
  for callback in f.success_callbacks:
    if callback.kind == VkFunction:
      # Execute Gene function with value as argument
      # We need a VM instance to execute, but we don't have one here
      # This will be handled by update_from_nim_future which has VM access
      discard
    # For now, callbacks are stored but not executed here
    # They will be executed by update_from_nim_future or by explicit VM call

proc fail*(f: FutureObj, error: Value) =
  if f.state != FsPending:
    not_allowed("Future already completed")
  f.state = FsFailure
  f.value = error
  # Execute failure callbacks
  for callback in f.failure_callbacks:
    if callback.kind == VkFunction:
      # Execute Gene function with error as argument
      # We need a VM instance to execute, but we don't have one here
      # This will be handled by update_from_nim_future which has VM access
      discard
    # For now, callbacks are stored but not executed here
    # They will be executed by update_from_nim_future or by explicit VM call

proc update_from_nim_future*(f: FutureObj) =
  ## Check if the underlying Nim future has completed and update our state
  ## This should be called during event loop polling
  ## NOTE: This version doesn't execute callbacks - use update_future_from_nim in vm/async.nim for that
  if f.nim_future.isNil or f.state != FsPending:
    return  # No Nim future to check, or already completed

  if finished(f.nim_future):
    # Nim future has completed - copy its result
    if failed(f.nim_future):
      # Future failed with exception
      # TODO: Wrap exception properly when exception handling is ready
      f.state = FsFailure
      f.value = new_str_value("Async operation failed")
    else:
      # Future succeeded
      f.state = FsSuccess
      f.value = read(f.nim_future)

    # Execute appropriate callbacks
    if f.state == FsSuccess:
      for callback in f.success_callbacks:
        # TODO: Execute callback with value
        discard
    else:
      for callback in f.failure_callbacks:
        # TODO: Execute callback with error
        discard

#################### Enum ########################

proc new_enum*(name: string): EnumDef =
  return EnumDef(
    name: name,
    members: initTable[string, EnumMember]()
  )

proc new_enum_member*(parent: Value, name: string, value: int): EnumMember =
  return EnumMember(
    parent: parent,
    name: name,
    value: value
  )

proc to_value*(e: EnumDef): Value =
  let r = new_ref(VkEnum)
  r.enum_def = e
  return r.to_ref_value()

proc to_value*(m: EnumMember): Value =
  let r = new_ref(VkEnumMember)
  r.enum_member = m
  return r.to_ref_value()

proc add_member*(self: Value, name: string, value: int) =
  if self.kind != VkEnum:
    not_allowed("add_member can only be called on enums")
  let member = new_enum_member(self, name, value)
  self.ref.enum_def.members[name] = member

proc `[]`*(self: Value, name: string): Value =
  if self.kind != VkEnum:
    not_allowed("enum member access can only be used on enums")
  if name in self.ref.enum_def.members:
    return self.ref.enum_def.members[name].to_value()
  else:
    not_allowed("enum " & self.ref.enum_def.name & " has no member " & name)

#################### Native ######################

converter to_value*(f: NativeFn): Value {.inline.} =
  let r = new_ref(VkNativeFn)
  r.native_fn = f
  result = r.to_ref_value()

# Helper functions for new NativeFn signature
proc get_positional_arg*(args: ptr UncheckedArray[Value], index: int, has_keyword_args: bool): Value {.inline.} =
  ## Get positional argument (handles keyword offset automatically)
  let offset = if has_keyword_args: 1 else: 0
  return args[offset + index]

proc get_keyword_arg*(args: ptr UncheckedArray[Value], name: string): Value {.inline.} =
  ## Get keyword argument by name
  if args[0].kind == VkMap:
    return args[0].ref.map.get_or_default(name.to_key(), NIL)
  else:
    return NIL

proc has_keyword_arg*(args: ptr UncheckedArray[Value], name: string): bool {.inline.} =
  ## Check if keyword argument exists
  if args[0].kind == VkMap:
    return args[0].ref.map.hasKey(name.to_key())
  else:
    return false

proc get_positional_count*(arg_count: int, has_keyword_args: bool): int {.inline.} =
  ## Get the number of positional arguments
  if has_keyword_args: arg_count - 1 else: arg_count

# Helper functions specifically for native methods
proc get_self*(args: ptr UncheckedArray[Value], has_keyword_args: bool): Value {.inline.} =
  ## Get self object for native methods (always first positional argument)
  return get_positional_arg(args, 0, has_keyword_args)

proc get_method_arg*(args: ptr UncheckedArray[Value], index: int, has_keyword_args: bool): Value {.inline.} =
  ## Get method argument by index (index 0 = first argument after self)
  return get_positional_arg(args, index + 1, has_keyword_args)

proc get_method_arg_count*(arg_count: int, has_keyword_args: bool): int {.inline.} =
  ## Get the number of method arguments (excluding self)
  let positional_count = get_positional_count(arg_count, has_keyword_args)
  if positional_count > 0: positional_count - 1 else: 0

# Migration helpers
proc get_legacy_args*(args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): seq[Value] =
  ## Helper to convert to seq[Value] for easier migration
  result = newSeq[Value]()
  let offset = if has_keyword_args: 1 else: 0
  for i in offset..<arg_count:
    result.add(args[i])

proc create_gene_args*(args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  ## For functions that need Gene object temporarily during migration
  var gene_args = new_gene_value()
  let offset = if has_keyword_args: 1 else: 0
  for i in offset..<arg_count:
    gene_args.gene.children.add(args[i])
  return gene_args

# Helper for calling native functions with proper casting
proc call_native_fn*(fn: NativeFn, vm: VirtualMachine, args: openArray[Value], has_keyword_args: bool = false): Value {.inline.} =
  ## Helper to call native function with proper array casting
  if args.len == 0:
    return fn(vm, nil, 0, has_keyword_args)
  else:
    return fn(vm, cast[ptr UncheckedArray[Value]](args[0].unsafeAddr), args.len, has_keyword_args)

#################### Frame #######################
const INITIAL_FRAME_POOL_SIZE* = 1024

var FRAMES* {.threadvar.}: seq[Frame]

proc init*(self: var CallBaseStack) {.inline.} =
  self.data = newSeq[uint16](0)

proc reset*(self: var CallBaseStack) {.inline.} =
  if self.data.len > 0:
    self.data.setLen(0)

proc push*(self: var CallBaseStack, base: uint16) {.inline.} =
  self.data.add(base)

proc pop*(self: var CallBaseStack): uint16 {.inline.} =
  assert self.data.len > 0, "Call base stack underflow"
  let idx = self.data.len - 1
  result = self.data[idx]
  self.data.setLen(idx)

proc peek*(self: CallBaseStack): uint16 {.inline.} =
  assert self.data.len > 0, "Call base stack is empty"
  result = self.data[self.data.len - 1]

proc is_empty*(self: CallBaseStack): bool {.inline.} =
  self.data.len == 0

proc reset_frame*(self: Frame) {.inline.} =
  # Reset only necessary fields, avoiding full memory clear
  self.kind = FkFunction
  self.caller_frame = nil
  self.caller_address = Address()
  self.caller_context = nil
  self.ns = nil
  self.scope = nil
  self.target = NIL
  # self field removed - self is now the first argument
  self.args = NIL
  self.current_method = nil
  self.stack_index = 0
  self.call_bases.reset()
  # Stack array will be overwritten as needed, no need to clear

proc free*(self: var Frame) =
  {.push checks: off, optimization: speed.}
  self.ref_count.dec()
  if self.ref_count <= 0:
    if self.caller_frame != nil:
      self.caller_frame.free()
    # Only free scope if frame owns it (functions without parameters borrow parent scope)
    # For now, we rely on IkScopeEnd to manage scopes properly
    # TODO: Track whether frame owns or borrows its scope
    if self.scope != nil and false:  # Disabled for now - IkScopeEnd handles it
      self.scope.free()
    self.reset_frame()
    FRAMES.add(self)
  {.pop.}

var FRAME_ALLOCS* {.threadvar.}: int
var FRAME_REUSES* = 0

proc new_frame*(): Frame {.inline.} =
  {.push boundChecks: off, overflowChecks: off.}
  if FRAMES.len > 0:
    result = FRAMES.pop()
    FRAME_REUSES.inc()
  else:
    result = cast[Frame](alloc0(sizeof(FrameObj)))
    FRAME_ALLOCS.inc()
  result.ref_count = 1
  result.stack_index = 0  # Reset stack index
  result.call_bases.init()
  {.pop.}

proc new_frame*(ns: Namespace): Frame {.inline.} =
  result = new_frame()
  result.ns = ns

proc new_frame*(caller_frame: Frame, caller_address: Address): Frame {.inline.} =
  result = new_frame()
  caller_frame.ref_count.inc()
  result.caller_frame = caller_frame
  result.caller_address = caller_address

proc new_frame*(caller_frame: Frame, caller_address: Address, scope: Scope): Frame {.inline.} =
  result = new_frame()
  caller_frame.ref_count.inc()
  result.caller_frame = caller_frame
  result.caller_address = caller_address
  result.scope = scope

proc update*(self: var Frame, f: Frame) {.inline.} =
  {.push checks: off, optimization: speed.}
  f.ref_count.inc()
  if self != nil:
    self.free()
  self = f
  {.pop.}

template current*(self: Frame): Value =
  self.stack[self.stack_index - 1]

proc replace*(self: var Frame, v: Value) {.inline.} =
  {.push boundChecks: off, overflowChecks: off.}
  self.stack[self.stack_index - 1] = v
  {.pop.}

template push*(self: var Frame, value: sink Value) =
  {.push boundChecks: off, overflowChecks: off.}
  self.stack[self.stack_index] = value
  self.stack_index.inc()
  {.pop.}

proc pop*(self: var Frame): Value {.inline.} =
  {.push boundChecks: off, overflowChecks: off.}
  self.stack_index.dec()
  result = self.stack[self.stack_index]
  self.stack[self.stack_index] = NIL
  {.pop.}

template pop2*(self: var Frame, to: var Value) =
  {.push boundChecks: off, overflowChecks: off.}
  self.stack_index.dec()
  copy_mem(to.addr, self.stack[self.stack_index].addr, 8)
  self.stack[self.stack_index] = NIL
  {.pop.}

proc push_call_base*(self: Frame) {.inline.} =
  assert self.stack_index > 0, "Cannot push call base without callee on stack"
  let base = self.stack_index - 1
  self.call_bases.push(base)

proc peek_call_base*(self: Frame): uint16 {.inline.} =
  self.call_bases.peek()

proc pop_call_base*(self: Frame): uint16 {.inline.} =
  self.call_bases.pop()

proc call_arg_count_from*(self: Frame, base: uint16): int {.inline.} =
  let stack_top = int(self.stack_index)
  let base_index = int(base)
  assert stack_top >= base_index + 1, "Call base exceeds stack height"
  stack_top - (base_index + 1)

proc pop_call_arg_count*(self: Frame): int {.inline.} =
  let base = self.pop_call_base()
  self.call_arg_count_from(base)

#################### COMPILER ####################

proc to_value*(self: ScopeTracker): Value =
  let r = new_ref(VkScopeTracker)
  r.scope_tracker = self
  result = r.to_ref_value()

proc new_compilation_unit*(): CompilationUnit =
  CompilationUnit(
    id: new_id(),
    trace_root: nil,
    instruction_traces: @[],
    inline_caches: @[],
  )

proc add_instruction*(self: CompilationUnit, instr: Instruction, trace: SourceTrace = nil) =
  if self.instruction_traces.len < self.instructions.len:
    self.instruction_traces.setLen(self.instructions.len)
  self.instructions.add(instr)
  self.instruction_traces.add(trace)

proc ensure_trace_capacity*(self: CompilationUnit) =
  if self.instruction_traces.len < self.instructions.len:
    self.instruction_traces.setLen(self.instructions.len)

proc replace_traces_range*(self: CompilationUnit, start_pos, end_pos: int, replacement_count: int) =
  if self.instruction_traces.len < self.instructions.len:
    self.instruction_traces.setLen(self.instructions.len)
  let clamped_start = max(0, min(start_pos, self.instruction_traces.len))
  let clamped_end = max(clamped_start, min(end_pos, self.instruction_traces.len - 1))
  if clamped_start <= clamped_end:
    let remove_count = clamped_end - clamped_start + 1
    for _ in 0..<remove_count:
      self.instruction_traces.delete(clamped_start)
  if replacement_count > 0:
    let insert_pos = min(clamped_start, self.instruction_traces.len)
    for _ in 0..<replacement_count:
      if insert_pos >= self.instruction_traces.len:
        self.instruction_traces.add(nil)
      else:
        self.instruction_traces.insert(nil, insert_pos)

proc `$`*(self: Instruction): string =
  case self.kind
    of IkPushValue,
      IkVar, IkVarResolve, IkVarAssign,
      IkAddValue, IkVarAddValue, IkVarSubValue, IkVarMulValue, IkVarDivValue,
      IkIncVar, IkDecVar,
      IkLtValue, IkVarLtValue, IkVarLeValue, IkVarGtValue, IkVarGeValue, IkVarEqValue,
      IkMapSetProp, IkMapSetPropValue,
      IkResolveSymbol, IkResolveMethod,
      IkSetMember, IkGetMember, IkGetMemberOrNil, IkGetMemberDefault,
      IkSetChild, IkGetChild,
      IkTailCall:
      if self.label.int > 0:
        result = fmt"{self.label.int32.to_hex()} {($self.kind)[2..^1]:<20} {$self.arg0}"
      else:
        result = fmt"         {($self.kind)[2..^1]:<20} {$self.arg0}"
    of IkJump, IkJumpIfFalse, IkContinue, IkBreak:
      let target_label = self.arg0.int64.Label
      if self.label.int > 0:
        result = fmt"{self.label.int32.to_hex()} {($self.kind)[2..^1]:<20} {target_label.int:04X}"
      else:
        result = fmt"         {($self.kind)[2..^1]:<20} {target_label.int:04X}"
    of IkJumpIfMatchSuccess:
      let target_label = self.arg1.int64.Label
      if self.label.int > 0:
        result = fmt"{self.label.int32.to_hex()} {($self.kind)[2..^1]:<20} {$self.arg0} {target_label.int:04X}"
      else:
        result = fmt"         {($self.kind)[2..^1]:<20} {$self.arg0} {target_label.int:04X}"
    of IkVarResolveInherited, IkVarAssignInherited:
      result = fmt"         {($self.kind)[2..^1]:<20} {$self.arg0} {self.arg1}"

    else:
      if self.label.int > 0:
        result = fmt"{self.label.int32.to_hex()} {($self.kind)[2..^1]}"
      else:
        result = fmt"         {($self.kind)[2..^1]}"

proc `$`*(self: seq[Instruction]): string =
  var i = 0
  while i < self.len:
    let instr = self[i]
    result &= fmt"{i:03} {instr}" & "\n"
    case instr.kind:
      of IkFunction:
        i.inc(2)
      else:
        i.inc()

proc `$`*(self: CompilationUnit): string =
  "CompilationUnit " & $(cast[uint64](self.id)) & "\n" & $self.instructions

proc new_label*(): Label =
  result = rand(int16.high).Label

proc find_label*(self: CompilationUnit, label: Label): int =
  var i = 0
  while i < self.instructions.len:
    let inst = self.instructions[i]
    if inst.label == label:
      while self.instructions[i].kind == IkNoop:
        i.inc()
      return i
    i.inc()
  not_allowed("Label not found: " & $label)

proc find_loop_start*(self: CompilationUnit, pos: int): int =
  var pos = pos
  while pos > 0:
    pos.dec()
    if self.instructions[pos].kind == IkLoopStart:
      return pos
  not_allowed("Loop start not found")

proc find_loop_end*(self: CompilationUnit, pos: int): int =
  var pos = pos
  while pos < self.instructions.len - 1:
    pos.inc()
    if self.instructions[pos].kind == IkLoopEnd:
      return pos
  not_allowed("Loop end not found")

proc scope_tracker*(self: Compiler): ScopeTracker =
  if self.scope_trackers.len > 0:
    return self.scope_trackers[^1]

#################### Instruction #################

converter to_value*(i: Instruction): Value =
  let r = new_ref(VkInstruction)
  r.instr = i
  result = r.to_ref_value()

converter to_value*(t: Thread): Value {.inline.} =
  let r = new_ref(VkThread)
  r.thread = t
  return r.to_ref_value()

converter to_value*(m: ThreadMessage): Value {.inline.} =
  let r = new_ref(VkThreadMessage)
  r.thread_message = m
  return r.to_ref_value()

proc new_instr*(kind: InstructionKind): Instruction =
  Instruction(
    kind: kind,
  )

proc new_instr*(kind: InstructionKind, arg0: Value): Instruction =
  Instruction(
    kind: kind,
    arg0: arg0,
  )

#################### VM ##########################

proc init_app_and_vm*() =
  # Reset gene namespace initialization flag since we're creating a new App
  gene_namespace_initialized = false

  VM = VirtualMachine(
    exception_handlers: @[],
    current_exception: NIL,
    symbols: addr SYMBOLS,
    pending_futures: @[],  # Initialize empty list of pending futures
    thread_futures: initTable[int, FutureObj](),  # Initialize empty table for thread futures
    message_callbacks: @[],  # Initialize empty list of message callbacks
    thread_local_ns: nil,  # Will be initialized after App is created
  )

  # Pre-allocate frame and scope pools
  if FRAMES.len == 0:
    FRAMES = newSeqOfCap[Frame](INITIAL_FRAME_POOL_SIZE)
    for i in 0..<INITIAL_FRAME_POOL_SIZE:
      FRAMES.add(cast[Frame](alloc0(sizeof(FrameObj))))
      FRAME_ALLOCS.inc()  # Count the pre-allocated frames


  if REF_POOL.len == 0:
    REF_POOL = newSeqOfCap[ptr Reference](INITIAL_REF_POOL_SIZE)
    for i in 0..<INITIAL_REF_POOL_SIZE:
      REF_POOL.add(cast[ptr Reference](alloc0(sizeof(Reference))))

  let r = new_ref(VkApplication)
  r.app = new_app()
  r.app.global_ns = new_namespace("global").to_value()
  r.app.gene_ns   = new_namespace("gene"  ).to_value()
  r.app.genex_ns  = new_namespace("genex" ).to_value()
  App = r.to_ref_value()

  # Create built-in GeneException class
  # TODO: Rename to Exception once symbol collision is fixed
  let exception_class = new_class("GeneException")
  let exception_ref = new_ref(VkClass)
  exception_ref.class = exception_class
  # Add to global namespace so it's accessible everywhere
  App.app.global_ns.ref.ns["GeneException".to_key()] = exception_ref.to_ref_value()

  # Add genex to global namespace (similar to gene-new)
  App.app.global_ns.ref.ns["genex".to_key()] = App.app.genex_ns

  # Pre-populate genex with commonly used extensions
  # This creates the namespace entry but doesn't load the extension yet
  App.app.genex_ns.ref.ns["http".to_key()] = NIL

  # Add time namespace stub to prevent errors
  let time_ns = new_namespace("time")
  # Simple time function that returns current timestamp
  proc time_now(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
    return epochTime().to_value()

  var time_now_fn = new_ref(VkNativeFn)
  time_now_fn.native_fn = time_now
  time_ns["now".to_key()] = time_now_fn.to_ref_value()
  App.app.global_ns.ref.ns["time".to_key()] = time_ns.to_value()
  # Also add to gene namespace for gene/time/now access
  App.app.gene_ns.ref.ns["time".to_key()] = time_ns.to_value()

  refresh_env_map()
  set_program_args("", @[])

  # Initialize thread-local namespace for main thread
  # This holds thread-specific variables like $thread and $main_thread
  VM.thread_local_ns = new_namespace("thread_local")

  # For main thread, $thread and $main_thread are the same
  let main_thread_ref = types.Thread(
    id: 0,
    secret: THREADS[0].secret
  )
  VM.thread_local_ns["$thread".to_key()] = main_thread_ref.to_value()
  VM.thread_local_ns["$main_thread".to_key()] = main_thread_ref.to_value()

  for callback in VmCreatedCallbacks:
    callback()

#################### Helpers #####################

proc refresh_env_map*() =
  if App == NIL or App.kind != VkApplication:
    return
  var env_table = initTable[Key, Value]()
  for pair in envPairs():
    env_table[pair.key.to_key()] = pair.value.to_value()
  App.app.gene_ns.ref.ns["env".to_key()] = new_map_value(env_table)

proc set_program_args*(program: string, args: seq[string]) =
  if App == NIL or App.kind != VkApplication:
    init_app_and_vm()
    if App == NIL or App.kind != VkApplication:
      return
  App.app.args = args
  let arr_ref = new_ref(VkArray)
  arr_ref.arr = @[]
  for arg in args:
    arr_ref.arr.add(arg.to_value())
  App.app.gene_ns.ref.ns["args".to_key()] = arr_ref.to_ref_value()
  App.app.gene_ns.ref.ns["program".to_key()] = program.to_value()

const SYM_UNDERSCORE* = SYMBOL_TAG or 0
const SYM_SELF* = SYMBOL_TAG or 1
const SYM_GENE* = SYMBOL_TAG or 2
const SYM_NS* = SYMBOL_TAG or 3
const SYM_CONTAINER* = SYMBOL_TAG or 4

proc init_values*() =
  SYMBOLS = ManagedSymbols()
  discard "_".to_symbol_value()
  discard "self".to_symbol_value()
  discard "gene".to_symbol_value()
  discard "container".to_symbol_value()

init_values()

include ./utils
