Aspect Oriented Programming (AOP)
================================

Aspect: cross-cutting concern, group of advices
Advice: individual action
Target: object to which aspect is applied (class, function)
Join Point: where advice is applied (before, after, around function/method/initialization/destruction/exception)
Interception: application of aspect to target

Aspect types:
Function aspects
Class aspects

Advice types:
Before / before filter
After
Around
Invariant (before and after)
After initialization - applicable to classes only
Before destruction - applicable to classes only
After exception

Join points:
Function: before, after, around, exception
Class: initialization, destruction, before/after/around/exception methods

Aspect instance: an aspect applied to a target
Aspect applied to a function can be called like a function

Shorthand:
An advice is an aspect with a single advice and can be applied to a target.
(fn fn [a b] (print "f" a b))
(before f [a b] (print "before f" a b))

```lisp
# Aspects are defined like
(fn_aspect A # fn_aspect is a temporary name
  (before []
    (print "before")
  )
  (after []
    (print "after")
  )
)
(fn f [] (print "f"))
(var f2 (A .apply f)) # f2 is a new callable with aspect A applied
(A .apply_in_place f) # f is modified with aspect A applied
(A .disable) # disable aspect A
(A .enable)  # enable aspect A

# Advices can be defined and applied separately
(var b (before [] (print "before")))
(b .apply f) # returns a new callable with advice b applied
(b .apply_in_place f)
(b .disable)
(b .enable)
```

```lisp
# Class aspects
(aspect A
  (on_apply [before_methods after_methods]
    (print "on_apply")
    (/before_methods = before_methods)
    (/after_methods = after_methods)
  )

  (before_init []
    (print "on_init")
  )
  (after_init []
    (print "after_init")
  )
  (before /before_methods []
    (print "before")
  )
  (after /after_methods []
    (print "after")
  )
)
(class C
  (fn f []
    (print "f")
  )
)
(A .apply C [m1] [m2]) # Class aspects are always applied in place
```

Execution:
IkUnifiedCall* will check whether the callable is an aspect instance (or applied aspect), if so it will execute the advices and the target function. A status object is created to store the state of the execution (index of the current advice, arguments, return value, etc.)

Questions:
1. How are arguments processed?
A: we'll reuse the new sequence created to house the arguments, an extra argument can be added to the end to store the return value (for after advices) or wrapped object (for around advices)
IkReturn will be updated to store the return value in the extra argument or to the calling stack frame depending on whether the function is called by an aspect or not.

I've reviewed the AOP design document. Here are my questions/clarifications:

apply vs apply_in_place semantics:
  .apply f returns a new callable, leaving f unchanged
  .apply_in_place f modifies f directly
  Is this correct? If so, what happens if f is referenced elsewhere when using apply_in_place?
A: yes we want to be able to update f's behavior even if it's referenced elsewhere.

before_filter vs before: The doc mentions "Before / before filter" but doesn't define how before_filter differs from before. I assume before_filter can skip execution (return falsy to abort) while before always proceeds?
A: before_filter is a before advice that can skip execution, before always proceeds

Around advice and wrapped: How does around call the wrapped target? Is there a special variable like wrapped, or a proceed function?
A: call the wrapped bound method directly like (wrapped ...). Wrapped is a regular argument passed to the around advice at the end.

Advice ordering with multiple aspects: If multiple aspects are applied, what's the execution order? LIFO (last applied runs first) or FIFO?
A: before and after are FIFO, there should be only one around advice per aspect instance.

Enable/disable scope: Does (A .disable) disable globally or per-instance? What about concurrent code?
A: disable/enable applies to all instances of the aspect. Concurrent code is not supported. Potentially we can add a per-instance enable/disable in the future.

Method-level aspects on classes: For class aspects like (before []), how are methods specified - by strings, regular expressions, variable?
A: we can use any of those. They must be resolved to a list of methods at apply-time.

Implementation approach: The doc mentions IkUnifiedCall* checking for aspect instances. Would it be simpler to compile aspects into the callable at apply-time (like we discussed earlier with WrappedCallable), avoiding runtime dispatch overhead?
A: no it has to be runtime because Gene is too flexible. However we can minimize overhead by having new type of callables for intercepted functions / methods.

## Here are the main gaps still remaining for class AOP as it stands:

  - No constructor interception: Aspect.apply only wraps entries in class.methods, so .ctor/.ctor! can’t be intercepted today.
  - No per‑instance enable/disable or unapply/reset; once applied it’s permanent and class‑wide.
  - Only one around advice per placeholder; no stacking/priority/ordering controls beyond FIFO for before/after.
  - Advices only receive positional args; original keyword args aren’t exposed or auto‑forwarded.
  - No function-level AOP (only instance methods on classes).
  - No async advice isolation or special error handling; advice exceptions just propagate.
