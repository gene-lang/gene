# Constructor Validation

## ADDED Requirements

### Requirement: Constructor Type Validation
The compiler SHALL validate that constructor calls match the constructor type defined in the class and handle `new!` calls with unevaluated arguments. Runtime validation SHALL also protect dynamic instantiations.

#### Scenario: Regular constructor with regular instantiation
**WHEN** a class is defined with a regular constructor (`.ctor`) and instantiated with `new`
**THEN** the instantiation SHALL succeed
**AND** arguments SHALL be evaluated before being passed to the constructor.

```gene
(class Person
  (.ctor [name age]
    (/name = name)
    (/age = age)
  )
)

(var p (new Person "Alice" 30))  # Should succeed
```

#### Scenario: Macro constructor with macro instantiation
**WHEN** a class is defined with a macro constructor (`.ctor!`) and instantiated with `new!`
**THEN** the compiler SHALL handle arguments as unevaluated symbols
**AND** arguments SHALL be passed to the constructor without evaluation.

```gene
(class LazyPerson
  (.ctor! [name age]
    (/name = ($caller_eval name))
    (/age = ($caller_eval age))
  )
)

(var p (new! LazyPerson name age))  # Should succeed, name and age passed unevaluated
```

#### Scenario: Regular constructor with macro instantiation (compile-time error)
**WHEN** a class is defined with a regular constructor but instantiated with `new!`
**THEN** the compiler SHALL throw a clear error message
**AND** the error SHALL indicate that the class has a regular constructor.

```gene
(class Person
  (.ctor [name age]
    (/name = name)
    (/age = age)
  )
)

(var p (new! Person "Alice" 30))  # Should throw: "Constructor mismatch: Class 'Person' has a regular constructor, use 'new' instead of 'new!'"
```

#### Scenario: Macro constructor with regular instantiation (compile-time error)
**WHEN** a class is defined with a macro constructor but instantiated with `new`
**THEN** the compiler SHALL throw a clear error message
**AND** the error SHALL indicate that the class has a macro constructor.

```gene
(class LazyPerson
  (.ctor! [name age]
    (/name = ($caller_eval name))
    (/age = ($caller_eval age))
  )
)

(var p (new LazyPerson name age))  # Should throw: "Constructor mismatch: Class 'LazyPerson' has a macro constructor, use 'new!' instead of 'new'"
```

### Requirement: Constructor Type Tracking
Classes SHALL track whether they have a macro constructor for compile-time validation.

#### Scenario: Constructor type tracking accuracy
**WHEN** a class is defined with either a regular or macro constructor
**THEN** the class metadata SHALL correctly indicate the constructor type
**AND** this information SHALL be available for compile-time validation.

```gene
(class RegularClass
  (.ctor [x]
    (/value = x)
  )
)
# Class should have has_macro_constructor = false

(class MacroClass
  (.ctor! [x]
    (/value = ($caller_eval x))
  )
)
# Class should have has_macro_constructor = true
```


#### Scenario: Class with regular constructor
**WHEN** a class is defined with a regular constructor
**THEN** the class SHALL have `has_macro_constructor = false`.

```gene
(class RegularClass
  (.ctor [x]
    (/value = x)
  )
)
# Class should have has_macro_constructor = false
```

#### Scenario: Class with macro constructor
**WHEN** a class is defined with a macro constructor
**THEN** the class SHALL have `has_macro_constructor = true`.

```gene
(class MacroClass
  (.ctor! [x]
    (/value = ($caller_eval x))
  )
)
# Class should have has_macro_constructor = true
```

#### Scenario: Class without constructor
**WHEN** a class is defined without any constructor
**THEN** the class SHALL have `has_macro_constructor = false`.

```gene
(class NoConstructorClass)
# Class should have has_macro_constructor = false
```

### Requirement: Inheritance Constructor Validation
Constructor validation SHALL work correctly through inheritance chains.

#### Scenario: Child class inherits parent's constructor type
**WHEN** a child class inherits from a parent and both use appropriate constructor calls
**THEN** instantiation SHALL succeed regardless of constructor type.

```gene
(class Base
  (.ctor [x]
    (/base_value = x)
  )
)

(class Derived < Base
  (.ctor [x y]
    (super .ctor x)
    (/derived_value = y)
  )
)

(var d (new Derived 10 20))  # Should succeed - both have regular constructors
```

### Requirement: Error Message Quality
Error messages SHALL be clear and actionable.

#### Scenario: Wrong constructor type error message
**WHEN** there is a constructor type mismatch
**THEN** the error message SHALL include the class name
**AND** SHALL provide clear guidance on what to use instead.

```gene
(class MyClass
  (.ctor [x]
    (/value = x)
  )
)

(new! MyClass 10)
# Expected error: "Constructor mismatch: Class 'MyClass' has a regular constructor, use 'new' instead of 'new!'"
```

### Requirement: Backward Compatibility
All existing code SHALL continue to work without changes.

#### Scenario: Existing regular constructor code
**WHEN** existing code uses regular constructors and `new`
**THEN** the code SHALL continue to work unchanged.

```gene
# This pattern should continue to work unchanged
(class Person
  (.ctor [name age]
    (/name = name)
    (/age = age)
  )
)

(var people [])
(for i 0 5
  (people .push (new Person ("Person" + i) (20 + i)))
)
```

### Requirement: Runtime Validation for Dynamic Instantiation
The VM SHALL validate constructor types at runtime to protect dynamic instantiations and provide clear error messages.

#### Scenario: Dynamic instantiation with macro constructor (runtime error)
**WHEN** a macro constructor is instantiated dynamically with evaluated arguments
**THEN** the VM SHALL throw a clear runtime error
**AND** the error SHALL indicate macro constructor requires `new!`.

```gene
(class LazyPerson
  (.ctor! [name age]
    (/name = ($caller_eval name))
    (/age = ($caller_eval age))
  )
)

# Dynamic instantiation that should fail
(var class_ref LazyPerson)
(var obj (new class_ref "Alice" 30))  # Should throw: "Cannot instantiate macro constructor 'LazyPerson' with evaluated arguments, use 'new!'"
```

#### Scenario: Dynamic instantiation with regular constructor (runtime error)
**WHEN** a regular constructor is instantiated dynamically with unevaluated arguments
**THEN** the VM SHALL throw a clear runtime error
**AND** the error SHALL indicate regular constructor requires `new`.

```gene
(class Person
  (.ctor [name age]
    (/name = name)
    (/age = age)
  )
)

# Dynamic instantiation that should fail
(var class_ref Person)
(var args_gene ["Alice" 30])
(var obj (new! class_ref args_gene))  # Should throw: "Cannot instantiate regular constructor 'Person' with unevaluated arguments, use 'new'"
```