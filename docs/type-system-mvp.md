# Type System MVP - Project Plan

**Project Lead:** Sunni (AI Assistant)  
**Started:** 2026-01-29  
**Target:** Q1 2026 (MVP)  
**Status:** 🟢 In Progress (~50% Complete)

## Vision

Transform Gene into a statically-typed language with:
- **Nominal typing** (not structural)
- **Type inference** (both compile-time and runtime)
- **Implicit `Any`** for gradual typing
- **Auto-converters** for ergonomics
- **AOT compilation** support

## MVP Scope (REVISED after audit)

### ✅ Phase 0: Already Complete!
The type checker already has:
- ✅ Type representation (TypeExpr)
- ✅ Type inference engine (unification)
- ✅ Generic type variables
- ✅ Function type checking
- ✅ Class/method types

### Phase 1: Enable & Integrate (Week 1) 🔥 PRIORITY
- [x] **Make type checking DEFAULT** (already enabled, type_check=true)
- [x] **Enable gradual typing** (strict=false, allows unknown types)
- [ ] Integrate with `nimble build` / `gene compile`
- [ ] Add `--no-type-check` flag for legacy code
- [ ] Fix any broken tests (may expose existing bugs)
- [x] Document how to add type annotations (dispatch-example.gene)

### Phase 2: Runtime Type Info (Week 2-3) 🎯 CORE MVP ✅ COMPLETE
- [x] Runtime type checking using NaN tags (runtime_types.nim)
- [x] Type validation helpers (is_int, is_float, etc.)
- [x] Type name extraction (runtime_type_name)
- [x] Type compatibility checking (is_compatible)
- [x] Implement `(x .is Type)` runtime check in VM
- [x] Runtime type validation on function calls (validate_type in args.nim)
- [x] Gene exceptions for type errors (catchable when try/catch fixed)
- [x] Class/instance type tracking (using InstanceObj.class_obj)
- [x] Inheritance support in `.is` checks
- [ ] Emit RTTI in compiled code for user types (deferred)

### Phase 3: `Any` Type & Gradual Typing (Week 4) ✅ COMPLETE
- [x] Make missing annotations default to `Any` (untyped params accept anything)
- [x] Remove strict mode requirement (strict=false in compiler)
- [x] Allow `Any -> Concrete` at runtime (deferred to runtime validation)
- [x] Test gradual migration path (8_gradual_typing.gene)
- [x] Class inheritance in type validation (runtime + compile-time)

### Phase 4: Auto-Converters (Week 5)
- [ ] Define conversion rules (Int -> Float safe, etc.)
- [ ] Implicit conversions at call sites
- [ ] Warning for lossy conversions
- [ ] Explicit syntax: `(x .to Float)`

### Phase 5: Dynamic Dispatch (Week 6)
- [ ] Function overloading by type signature
- [ ] Runtime dispatch based on argument types
- [ ] Cache for hot paths

### Phase 6: Polish & Docs (Week 7)
- [ ] Update all examples with types
- [ ] Migration guide
- [ ] Type error messages
- [ ] Performance benchmarks

## Current State Assessment ✅

### Existing Infrastructure
```
src/gene/type_checker.nim    1391 lines - COMPLETE TYPE CHECKER!
  - TypeExpr: Any, Named, Applied, Union, Fn, Var
  - Unification algorithm (subs table)
  - Type inference for expressions
  - Class type tracking
  - Scoped type environment
  
src/gene/types/              Type definitions
src/gene/compiler.nim        Uses type_checker (optional, line 4351)
src/gene/vm.nim              Runtime VM - NO TYPE INFO YET
```

### Discovery: Existing Type System! 🎉
Gene already has a **complete static type checker** that's:
- ✅ Hindley-Milner style inference
- ✅ Generic type variables
- ✅ Union types
- ✅ Function types with params
- ✅ Class/method types
- ❌ **NOT ENABLED BY DEFAULT**
- ❌ **NO RUNTIME TYPE INFO**

### Key Questions ANSWERED
1. ✅ **What does type_checker.nim do?** Full compile-time type inference & checking
2. ✅ **How are types represented?** TypeExpr ADT (TkAny, TkNamed, etc.)
3. ✅ **Existing inference?** YES! Unification-based, similar to ML/Haskell
4. ⚠️ **RTTI storage?** MISSING - types only exist at compile-time

## Next Actions

1. **[DONE]** Audit complete! Type system exists!
2. **[NEXT]** Enable type checking by default (Phase 1)
3. **[NEXT]** Prototype RTTI in Value struct (Phase 2)
4. **[DECISION NEEDED]** RTTI storage approach (see below)

## Decision Log

### 2026-01-29: Project Kickoff
- **Decision:** Start with MVP, nominal typing
- **Rationale:** User request - gradual migration path
- **Owner:** Guoliang Cao

### 2026-01-29: Type Checker Already Exists!
- **Discovery:** Full static type checker in src/gene/type_checker.nim
- **Impact:** Dramatically reduces MVP timeline (weeks not months)
- **Next:** Enable by default, add RTTI for runtime

### [DECISION NEEDED]: RTTI Storage

**Question:** Where to store runtime type information?

**Options:**
1. **Add `type_id: uint16` to Value** ✅ RECOMMENDED
   - Pros: Fast, direct access, works with NaN-boxing
   - Cons: Increases Value size (8 bytes -> 10 bytes, or clever packing)
   
2. **Separate type table (pointer-based lookup)**
   - Pros: No Value size increase
   - Cons: Slower, extra indirection, GC complexity
   
3. **Encode in NaN bits** (for NaN-boxed values)
   - Pros: No size increase
   - Cons: Complex, limited type space, Nim-specific tricks
   
4. **Hybrid: primitives use NaN, objects use header**
   - Pros: Best of both worlds
   - Cons: Most complex implementation

**Recommendation:** Option 1 - add type_id field. Simple, fast, proven approach.

**Your input needed:** Which option do you prefer?

## Resources

- [migrate-to-static-lang.md](./migrate-to-static-lang.md) - Architecture
- [ai-first-design.md](./ai-first-design.md) - Overall roadmap
- [type_checker.nim](../src/gene/type_checker.nim) - Existing code

## Communication

**Updates:** I'll ping in Slack when:
- Major milestone completes
- Blocking decision needed
- Design question arises
- Weekly progress summary

**Ask Guoliang:**
- Type representation choice (after audit)
- Auto-conversion priority list
- Interface syntax preferences (later phase)
