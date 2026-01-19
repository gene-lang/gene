# Gene Macro & Function Design

This document captures the design decisions for Gene's function, macro, and class construction system.

## Core Principle

The `!` suffix consistently indicates **unevaluated arguments** across all forms where it applies.

## Function Forms

| Form | Named | Evaluates Args | Usage |
|------|-------|----------------|-------|
| `fn` | ✓ | ✓ (unless name ends in `!`) | Named functions |
| `fn` with `name!` | ✓ | ✗ | Named macros |
| `fn` (anonymous) | ✗ | ✓ | Anonymous functions (lambdas) |

### Examples

```gene
# Named function
(fn add [a b]
  (a + b)
)

# Named macro (! in name signals unevaluated args)
(fn debug! [expr]
  (println "DEBUG:" expr)
  ($caller_eval expr)
)

# Anonymous function (lambda)
(var double (fn [x] (x * 2)))

# Named macro
(fn unless! [cond then]
  (if (! ($caller_eval cond))
    ($caller_eval then)
  )
)
```

### Parameter List

- Use `[]` for empty parameter lists
- The `_` placeholder is no longer supported; use `[]` instead

```gene
# Preferred
(fn hello []
  (println "Hello!")
)
```

## Class Forms

| Form | Evaluates Args | Notes |
|------|----------------|-------|
| `ctor` | ✓ | Standard constructor |
| `ctor!` | ✗ | Receives unevaluated args |
| `method` | ✓ (unless name ends in `!`) | Instance methods |
| `new` | ✓ | Calls `ctor` |
| `new!` | ✗ | Calls `ctor!` |

### Constructor Rules

- A class may define **either** `ctor` **or** `ctor!`, but not both
- `new` must be paired with `ctor`
- `new!` must be paired with `ctor!`
- Mismatched usage is a compile error

```gene
# Standard class with evaluated constructor
(class Point
  (ctor [x y]
    (/x = x)
    (/y = y)
  )
  (method distance []
    (sqrt ((/x * /x) + (/y * /y)))
  )
)

(var p (new Point 3 4))        # ✓
# (new! Point 3 4)             # Error: Point has ctor, not ctor!
```

```gene
# DSL-style class with unevaluated constructor
(class HtmlBuilder
  (ctor! [body]
    (/tree = body)  # Capture structure unevaluated
  )
  (method render []
    (process /tree)
  )
)

(var page (new! HtmlBuilder
  (div ^class "container"
    (h1 "Title")
    (p "Content")
  )
))
# (new HtmlBuilder ...)        # Error: HtmlBuilder has ctor!, not ctor
```

### Method Macros

Methods can also receive unevaluated arguments by ending the name with `!`:

```gene
(class Validator
  (ctor []
    (/rules = [])
  )
  
  (method add_rule! [condition message]
    # condition and message are unevaluated
    (/rules .push {^cond condition ^msg message})
  )
  
  (method validate [data]
    (for rule in /rules
      (if (! ($caller_eval rule/cond))
        (throw rule/msg)
      )
    )
  )
)
```

## Future Consideration: Dual Constructors

Currently prohibited, but may be allowed in the future if compelling use cases emerge:

```gene
# Hypothetical future syntax
(class Flexible
  (ctor [x]
    (/x = x)
  )
  (ctor! [x]
    (/x_expr = x)  # Store the expression itself
  )
)

(new Flexible 42)         # Calls ctor, /x = 42
(new! Flexible (+ 1 2))   # Calls ctor!, /x_expr = (+ 1 2) unevaluated
```

This would enable classes to support both eager and lazy construction modes. Deferred until real-world demand exists.

## Macro Evaluation

Within macro bodies, use `$caller_eval` to evaluate expressions in the caller's context:

```gene
(fn time! [expr]
  (var start (now))
  (var result ($caller_eval expr))
  (var elapsed ((now) - start))
  (println "Elapsed:" elapsed "ms")
  result
)

(time! (expensive_computation))
# Prints: Elapsed: 1234 ms
# Returns: result of expensive_computation
```

## Summary

The `!` suffix provides a uniform mechanism for controlling argument evaluation:

- **Function names ending in `!`**: macro behavior
- Anonymous macros are not supported; use a named macro (`fn name! [args] ...`).
- **`ctor!`**: unevaluated constructor args
- **`new!`**: invoke `ctor!`
- **Method names ending in `!`**: macro behavior

This keeps the keyword count minimal while enabling powerful metaprogramming patterns.
