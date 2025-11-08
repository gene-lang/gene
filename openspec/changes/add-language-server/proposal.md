# Proposal: Add Language Server for Gene

## Why

Gene currently lacks modern development tooling that would significantly improve developer experience and productivity. A Language Server Protocol (LSP) implementation would provide:

**Current Developer Experience Limitations:**
- Manual command-line execution with no IDE integration
- No real-time syntax checking or error feedback
- No code completion, navigation, or refactoring tools
- No hover information or go-to-definition functionality
- No project-wide symbol search or cross-reference analysis
- No integrated debugging with breakpoints or variable inspection
- No formatting or code organization tools

**Developer Impact:**
- Gene developers must use external editors without language-aware features
- Learning curve is steeper due to lack of real-time feedback
- Code navigation and refactoring requires manual file searching
- Error discovery happens at runtime rather than edit time
- No integrated documentation lookup or symbol information

**Industry Standard:**
- Language Server Protocol is the de-facto standard for language tooling
- Most modern IDEs (VS Code, IntelliJ, Emacs with LSP) support LSP
- Competitive Lisp-like languages (Clojure, Racket) have mature LSP implementations
- LSP provides universal accessibility across multiple editors and platforms

## What Changes

### Core Architecture
- **LSP Server Implementation**: Create new LSP-compliant server using Nim's `asynchttpserver`
- **Gene Language Integration**: Leverage existing parser, compiler, and VM for analysis
- **Incremental Parsing**: Reuse Gene's S-expression parser for incremental document analysis
- **Symbol Resolution**: Utilize existing namespace and scope systems for cross-references
- **Real-time Compilation**: Use existing compiler for syntax checking and type inference
- **VM Integration**: Leverage VM for runtime type checking and evaluation

### Specific Changes
- Add `src/genex/language_server.nim` with full LSP protocol implementation
- Add `src/gene/lsp/` module for Gene-specific language analysis
- Add `bin/gene-lsp` CLI entry point for LSP server
- Add `src/gene/compiler_analysis.nim` for incremental analysis
- Reuse existing `src/gene/parser.nim` for document parsing
- Extend `src/gene/types.nim` with LSP-specific data structures
- Add LSP configuration to build system and CLI

### **NEW** Features
- **Syntax Highlighting**: Real-time tokenization and semantic highlighting
- **Code Completion**: Symbol-aware completion for functions, variables, and keywords
- **Go to Definition**: Navigate to function/variable definitions across files
- **Hover Information**: Display type information and documentation on hover
- **Find References**: Locate all uses of a symbol across project
- **Rename Symbol**: Safe refactoring with scope-aware rename operations
- **Format Code**: Automatic S-expression formatting and normalization
- **Error Checking**: Real-time syntax and type error detection
- **Project Symbols**: Document outline and symbol search
- **Workspace Management**: Multi-file project awareness and configuration

### Non-Goals (Out of Scope)
- **Debugging Adapter**: VS Code debugging via LSP (future work)
- **Code Actions**: Source code generation or advanced refactoring (future work)
- **Multi-root Workspaces**: Complex project layouts (future work)
- **Performance Optimization**: Large file handling optimization (future work)
- **Custom LSP Extensions**: Gene-specific protocol extensions (future work)

## Impact

### Affected Specs
- **lsp** (NEW): Language Server Protocol implementation for Gene

### Affected Code
- **New Files**:
  - `src/genex/language_server.nim` (main LSP server implementation)
  - `src/gene/lsp/parser.nim` (incremental document analysis)
  - `src/gene/lsp/analyzer.nim` (symbol resolution and type checking)
  - `src/gene/lsp/handler.nim` (LSP request/response handling)
  - `src/gene/lsp/types.nim` (LSP protocol data structures)
  - `src/commands/lsp.nim` (LSP server CLI interface)
  - `bin/gene-lsp` (LSP server executable)
- **Modified Files**:
  - `src/gene/parser.nim` (extensions for incremental parsing)
  - `src/gene/compiler.nim` (hooks for analysis integration)
  - `src/gene/types.nim` (LSP-specific value types)
  - `src/gene/vm.nim` (VM access for runtime analysis)
  - `gene.nimble` (build configuration for LSP target)

### Migration Path
- **Seamless Integration**: LSP server works alongside existing Gene tools
- **Optional Enhancement**: Developers can use Gene with or without LSP as preferred
- **Backward Compatibility**: All existing CLI commands remain unchanged
- **Progressive Adoption**: Start with basic features, incrementally add advanced capabilities

### Risk Assessment
- **Low Complexity**: Leverage existing parser/compiler/VM architecture
- **Proven Technology**: Use well-established LSP libraries and patterns
- **Incremental Development**: Start with core LSP features, expand gradually
- **Minimal Disruption**: New functionality is additive, not breaking changes
- **Resource Usage**: Server runs in background with minimal memory footprint

### Performance Characteristics
- **Startup Time**: <2 seconds for typical project initialization
- **Response Latency**: <50ms for most LSP requests (completion, hover)
- **Memory Usage**: <50MB for medium-sized projects
- **CPU Overhead**: <5% during active development
- **Scalability**: Handles projects with 1000+ Gene files efficiently

### Timeline Estimate
- **Phase 1 (Core LSP)**: 3-4 weeks - Basic protocol implementation
- **Phase 2 (Language Analysis)**: 2-3 weeks - Gene-specific features
- **Phase 3 (Advanced Features)**: 2-3 weeks - Completion, navigation, refactoring
- **Phase 4 (Integration & Polish)**: 1-2 weeks - Testing, documentation, optimization

**Total: 8-12 weeks** for full-featured LSP implementation

### Benefits
- **Modern Development Experience**: IDE integration with real-time feedback
- **Increased Productivity**: Code completion, navigation, and refactoring tools
- **Better Error Detection**: Syntax and type errors at edit time, not runtime
- **Cross-Platform Compatibility**: Works with any LSP-compatible editor
- **Language Adoption**: Lower barrier to entry for new Gene developers
- **Professional Tooling**: Matches capabilities of modern language ecosystems
- **Extensible Foundation**: Base for future debugging and advanced tooling features

## Open Questions

1. **LSP Feature Prioritization**:
   - Should we prioritize completion, navigation, or error checking first?
   error checking -> navigation -> completion
   - Which LSP capabilities are most critical for Gene's target users?
   syntax highlighting -> error checking -> navigation -> completion

2. **Editor Integration Strategy**:
   - Should we provide specific setup instructions for VS Code, Emacs, Vim?
   yes for VS code
   - Should we bundle configuration files for common editors?
   yes for VS code

3. **Performance Trade-offs**:
   - What are acceptable startup time and memory usage limits?
   startup time < 1 seconds
   - Should we support incremental analysis for very large files (>10MB)?
   no

4. **VS Code Extension**:
   - Should we create an official Gene VS Code extension alongside LSP server?
   yes
   - Should extension include Gene-specific features beyond standard LSP?
   no, maybe later

5. **Documentation Generation**:
   - Should LSP server provide documentation from inline comments?
   - **Decision**: Add in Phase 4 after core features are stable
   - Should we integrate with existing doc generation systems?
   - **Decision**: Future enhancement after initial LSP release