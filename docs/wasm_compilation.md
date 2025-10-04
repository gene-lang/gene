# Gene WebAssembly Compilation Guide

This document describes how to compile Gene to WebAssembly for running in the browser.

## Current Status

**✅ Working**: JavaScript-based Gene REPL in `web/gene_repl.html`
- Simplified Gene interpreter written in pure JavaScript
- Runs entirely in the browser with no compilation needed
- Supports basic Gene features: variables, functions, control flow, lists

**⚠️ In Progress**: Full Gene VM compilation to WASM/JS
- The native Gene VM uses C-like dependencies (PCRE, OS APIs)
- These need to be adapted or removed for JavaScript/WASM targets

## Approach 1: Nim JavaScript Backend (Simpler)

Compile Gene directly to JavaScript using Nim's built-in JS backend.

### Prerequisites

```bash
# Nim compiler with JS backend support (already installed)
nim --version
```

### Challenges

1. **Regex Library**: Gene uses `re` module which requires PCRE (C library)
   - **Solution**: Replace with `jsre` module for JavaScript
   - **Files to modify**: `src/gene/parser.nim` and any file using `import re`

2. **File I/O**: Different APIs between C and JavaScript
   - **Solution**: Use conditional compilation for browser vs native
   - **Example**: `when defined(js): ... else: ...`

3. **Platform-specific code**: OS APIs, threading, etc.
   - **Solution**: Create browser-compatible alternatives or stub them out

### Step-by-Step

1. **Create JS-compatible entry point**:
   ```nim
   # src/gene_browser.nim
   when defined(js):
     import jsre instead of re
     import jsffi for JavaScript interop

   proc evalGene*(code: cstring): cstring {.exportc.} =
     # Simplified evaluation for browser
     ...
   ```

2. **Compile to JavaScript**:
   ```bash
   nim js -d:release -o:web/gene.js src/gene_browser.nim
   ```

3. **Include in HTML**:
   ```html
   <script src="gene.js"></script>
   <script>
     const result = evalGene("(+ 1 2 3)");
   </script>
   ```

### Estimated Effort

- **Small (1-2 days)**: Minimal Gene subset with basic features
- **Medium (1 week)**: Most Gene features excluding file I/O, threading
- **Large (2-3 weeks)**: Full Gene language with workarounds for all features

## Approach 2: WebAssembly via Emscripten (More Complex)

Compile Nim/C code to WebAssembly for better performance.

### Prerequisites

```bash
# Install Emscripten SDK
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh
```

### Process

1. **Compile Nim to C**:
   ```bash
   nim c --os:linux --cpu:wasm32 --cc:clang \
     --clang.exe:emcc --clang.linkerexe:emcc \
     --nimcache:build/nimcache \
     -d:release -d:noSignalHandler \
     --out:build/gene.js \
     src/gene_wasm.nim
   ```

2. **Additional Emscripten flags** (add to nim.cfg):
   ```
   --passC:"-s WASM=1"
   --passL:"-s EXPORTED_FUNCTIONS=['_evalGene','_initVM']"
   --passL:"-s MODULARIZE=1"
   --passL:"-s EXPORT_NAME='GeneModule'"
   ```

3. **Load in browser**:
   ```javascript
   GeneModule().then(function(Module) {
     const evalGene = Module.cwrap('evalGene', 'string', ['string']);
     const result = evalGene('(+ 1 2 3)');
     console.log(result);
   });
   ```

### Challenges

- More complex toolchain
- Larger binary size (~500KB+ for WASM)
- Async loading required
- Need to handle memory management carefully

### Estimated Effort

- **Setup (2-3 days)**: Configure Emscripten, create build system
- **Implementation (1-2 weeks)**: Adapt Gene code for WASM
- **Testing & Optimization (3-5 days)**: Debug issues, reduce binary size

## Approach 3: Hybrid (Recommended for Production)

Use JavaScript for UI and WASM for performance-critical parts.

### Architecture

```
┌─────────────────────────────────────┐
│         Web Interface (HTML/CSS)     │
├─────────────────────────────────────┤
│   JavaScript Layer                  │
│   - REPL UI                         │
│   - Syntax highlighting             │
│   - State management                │
├─────────────────────────────────────┤
│   Gene Core (WASM Module)           │
│   - Parser                          │
│   - Compiler                        │
│   - VM execution                    │
└─────────────────────────────────────┘
```

### Benefits

- Fast UI updates (JavaScript)
- Fast execution (WASM)
- Easier debugging (can fall back to JS)
- Progressive enhancement (works without WASM)

## Current Implementation

The `web/gene_repl.html` uses **Approach 3** with JavaScript-only implementation:

```javascript
class GeneVM {
  constructor() {
    this.scope = new Map();
    this.functions = new Map();
    // ...
  }

  eval(code) {
    // Parse and evaluate Gene code
    // ...
  }
}
```

### Supported Features

✅ **Working**:
- Variables: `(var x 42)`
- Math: `(+ 1 2 3)`, `(* 5 10)`
- Comparisons: `(> x 10)`, `(== a b)`
- Conditionals: `(if condition then else)`
- Functions: `(fn name [params] body)`
- Loops: `(for var in list body)`, `(while condition body)`
- Lists: `[1 2 3]`, `(first list)`, `(length list)`
- I/O: `(println "text")`

⚠️ **Limited**:
- No classes/OOP
- No macros
- No async/await
- No file I/O
- No module system
- No native extensions

## Next Steps

### For Simple Use Cases
Continue using the JavaScript implementation in `web/gene_repl.html`.

### For Full Gene Support

1. **Option A: Pure JavaScript**
   - Implement remaining Gene features in JavaScript
   - Simpler to maintain and debug
   - Good for educational/demo purposes

2. **Option B: Compile to WASM**
   - Create `src/gene_browser.nim` with browser-compatible code
   - Replace platform-specific dependencies
   - Set up build pipeline
   - Better performance for complex programs

3. **Option C: Web Worker**
   - Run Gene evaluation in Web Worker for non-blocking execution
   - Keep UI responsive during long computations
   - Useful for both JS and WASM implementations

## Example: Converting Parser to JS-compatible

**Before** (`src/gene/parser.nim`):
```nim
import re

proc parse(input: string): Value =
  let regex = re"[0-9]+"  # PCRE regex
  if input.match(regex):
    # ...
```

**After** (`src/gene/parser_browser.nim`):
```nim
when defined(js):
  import jsre  # JavaScript regex

  proc parse(input: string): Value =
    let regex = newRegExp("[0-9]+")  # JS regex
    if input.test(regex):
      # ...
else:
  import re  # Native regex

  proc parse(input: string): Value =
    let regex = re"[0-9]+"
    if input.match(regex):
      # ...
```

## Resources

- [Nim JS Backend Docs](https://nim-lang.org/docs/backends.html#backends-the-javascript-target)
- [Emscripten Documentation](https://emscripten.org/docs/)
- [WebAssembly Specification](https://webassembly.github.io/spec/)
- [Gene Language Repository](https://github.com/gcao/gene)

## Conclusion

For most users, the current JavaScript-based REPL in `web/gene_repl.html` provides a good interactive Gene experience in the browser. For production use cases requiring full Gene compatibility, a hybrid approach with WASM for core execution would be recommended.
