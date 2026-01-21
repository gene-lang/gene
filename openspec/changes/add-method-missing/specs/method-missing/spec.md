## ADDED Requirements

### Requirement: Method Missing Hook Definition
Classes SHALL support a `method_missing` method that is invoked when a called method does not exist on the class or its ancestors.

#### Scenario: Define method_missing on a class
- **GIVEN** a class with `method_missing` defined
- **WHEN** a non-existent method is called on an instance
- **THEN** `method_missing` is invoked with the method name and arguments

```gene
(class DynamicProxy
  (method method_missing [name args...]
    (println "Called: " name " with " args)
    (+ 100 (args/0))
  )
)

(var proxy (new DynamicProxy))
(proxy .foo 42)  # Calls method_missing with "foo" and [42], returns 142
```

### Requirement: Method Missing Signature
The `method_missing` method SHALL receive the method name as the first argument and all original arguments as remaining arguments.

#### Scenario: Method missing receives correct arguments
- **GIVEN** a class with `method_missing [name args...]`
- **WHEN** `(obj .some_method a b c)` is called and `some_method` does not exist
- **THEN** `method_missing` receives `"some_method"` as `name` and `[a b c]` as `args`

```gene
(class ArgCapture
  (ctor []
    (/captured = NIL)
  )
  (method method_missing [name args...]
    (/captured = {^name name ^args args})
    NIL
  )
  (method get_captured _ /captured)
)

(var obj (new ArgCapture))
(obj .test_method 1 2 3)
(var cap (obj .get_captured))
(assert (cap/name == "test_method"))
(assert (cap/args == [1 2 3]))
```

### Requirement: Method Missing Inheritance
When a class does not define `method_missing` but an ancestor does, the ancestor's `method_missing` SHALL be invoked for missing methods.

#### Scenario: Child inherits parent's method_missing
- **GIVEN** a parent class with `method_missing` and a child class without
- **WHEN** a non-existent method is called on a child instance
- **THEN** the parent's `method_missing` is invoked

```gene
(class BaseProxy
  (method method_missing [name args...]
    (str "proxied:" name)
  )
)

(class ChildProxy < BaseProxy
  (method real_method _ "real")
)

(var child (new ChildProxy))
(assert ((child .real_method) == "real"))
(assert ((child .unknown) == "proxied:unknown"))
```

#### Scenario: Child can override method_missing
- **GIVEN** a parent class with `method_missing` and a child with its own `method_missing`
- **WHEN** a non-existent method is called on a child instance
- **THEN** the child's `method_missing` is invoked

```gene
(class BaseProxy
  (method method_missing [name args...]
    "base"
  )
)

(class ChildProxy < BaseProxy
  (method method_missing [name args...]
    "child"
  )
)

(var child (new ChildProxy))
(assert ((child .anything) == "child"))
```

### Requirement: Method Missing Priority
Regular methods SHALL take precedence over `method_missing`. The hook is only invoked when no matching method exists in the class hierarchy.

#### Scenario: Defined methods take precedence
- **GIVEN** a class with both `method_missing` and a regular method `foo`
- **WHEN** `foo` is called
- **THEN** the regular method is invoked, not `method_missing`

```gene
(class MixedClass
  (method foo _ "real foo")
  (method method_missing [name args...]
    "missing"
  )
)

(var obj (new MixedClass))
(assert ((obj .foo) == "real foo"))
(assert ((obj .bar) == "missing"))
```

### Requirement: Method Missing Return Value
The return value of `method_missing` SHALL be the return value of the original method call.

#### Scenario: Return value propagates
- **GIVEN** `method_missing` returns a computed value
- **WHEN** a missing method is called
- **THEN** the caller receives the returned value

```gene
(class Calculator
  (method method_missing [name args...]
    (if (name == "double")
      ((args/0) * 2)
    elif (name == "triple")
      ((args/0) * 3)
    else
      0
    )
  )
)

(var calc (new Calculator))
(assert ((calc .double 5) == 10))
(assert ((calc .triple 5) == 15))
```

### Requirement: Method Missing Error Propagation
If `method_missing` throws an exception, it SHALL propagate to the caller as if the original method had thrown.

#### Scenario: Exceptions propagate from method_missing
- **GIVEN** `method_missing` throws an exception
- **WHEN** a missing method is called
- **THEN** the exception is received by the caller

```gene
(class StrictProxy
  (method method_missing [name args...]
    (throw (str "Unknown method: " name))
  )
)

(var obj (new StrictProxy))
(try
  (obj .unknown)
catch *
  (assert (($ex .message) == "Unknown method: unknown"))
)
```

### Requirement: No Method Missing Fallback
If a method is not found and no `method_missing` exists in the class hierarchy, the VM SHALL throw an error as before.

#### Scenario: Error without method_missing
- **GIVEN** a class without `method_missing`
- **WHEN** a non-existent method is called
- **THEN** an error is thrown

```gene
(class SimpleClass
  (method foo _ "foo")
)

(var obj (new SimpleClass))
(try
  (obj .bar)  # Should throw
catch *
  (assert true)
)
```
