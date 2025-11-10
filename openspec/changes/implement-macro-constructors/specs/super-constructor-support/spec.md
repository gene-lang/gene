# Super Constructor Support

## ADDED Requirements

### Requirement: Macro Super Constructor Syntax
Gene SHALL support `(super .ctor!)` syntax for calling parent macro constructors with unevaluated arguments.

#### Scenario: Macro super constructor call
**WHEN** a child class inherits from a parent with a macro constructor
**AND** the child calls `(super .ctor!)` with unevaluated arguments
**THEN** the parent constructor SHALL receive the arguments as unevaluated symbols
**AND** the inheritance SHALL work correctly.

```gene
(class Base
  (.ctor! [config]
    (/config = ($caller_eval config))
    (/initialized = true)
  )
)

(class Derived < Base
  (.ctor! [config extra]
    (super .ctor! config)  # Pass unevaluated config to parent
    (/extra = ($caller_eval extra))
  )
)

(var obj (new! Derived config_path extra_data))  # Should succeed
```

#### Scenario: Regular super constructor call (existing behavior)
**WHEN** a child class inherits from a parent with a regular constructor
**AND** the child calls `(super .ctor)` with evaluated arguments
**THEN** the behavior SHALL remain unchanged from current implementation.

```gene
(class Base
  (.ctor [config]
    (/config = config)
    (/initialized = true)
  )
)

(class Derived < Base
  (.ctor [config extra]
    (super .ctor config)  # Pass evaluated config to parent
    (/extra = extra)
  )
)

(var obj (new Derived "config.json" "extra"))  # Should continue to work
```

### Requirement: Super Constructor Type Validation
Gene SHALL validate that super constructor calls match the parent's constructor type.

#### Scenario: Mismatched super constructor call (error)
**WHEN** a child class tries to call `(super .ctor)` on a parent with a macro constructor
**THEN** the VM SHALL throw a clear error message
**AND** the error SHALL indicate the parent class has a macro constructor.

```gene
(class Base
  (.ctor! [config]
    (/config = ($caller_eval config))
  )
)

(class Derived < Base
  (.ctor [config extra]
    (super .ctor config)  # ERROR: Parent has macro constructor
    (/extra = extra)
  )
)

# Should throw: "Super constructor mismatch: Parent class 'Base' has a macro constructor, use '(super .ctor!)' instead of '(super .ctor)'"
```

#### Scenario: Reverse mismatched super constructor call (error)
**WHEN** a child class tries to call `(super .ctor!)` on a parent with a regular constructor
**THEN** the VM SHALL throw a clear error message
**AND** the error SHALL indicate the parent class has a regular constructor.

```gene
(class Base
  (.ctor [config]
    (/config = config)
  )
)

(class Derived < Base
  (.ctor! [config extra]
    (super .ctor! config)  # ERROR: Parent has regular constructor
    (/extra = ($caller_eval extra))
  )
)

# Should throw: "Super constructor mismatch: Parent class 'Base' has a regular constructor, use '(super .ctor)' instead of '(super .ctor!)'"
```

### Requirement: Mixed Constructor Types in Inheritance
Gene SHALL support inheritance chains with mixed constructor types when properly matched.

#### Scenario: Regular parent, macro child
**WHEN** a child class has a macro constructor but inherits from a parent with a regular constructor
**AND** the child properly evaluates arguments before passing to parent
**THEN** the inheritance SHALL work correctly.

```gene
(class Base
  (.ctor [value]
    (/base_value = value)
  )
)

(class Derived < Base
  (.ctor! [symbolic_value]
    (super .ctor ($caller_eval symbolic_value))  # Evaluate before passing to regular parent
    (/derived_symbol = symbolic_value)
  )
)

(var obj (new! Derived value_symbol))  # Should succeed
```

#### Scenario: Macro parent, regular child
**WHEN** a child class has a regular constructor but inherits from a parent with a macro constructor
**AND** the child properly quotes arguments for parent
**THEN** the inheritance SHALL work correctly.

```gene
(class Base
  (.ctor! [symbolic_value]
    (/base_symbol = symbolic_value)
    (/base_value = ($caller_eval symbolic_value))
  )
)

(class Derived < Base
  (.ctor [evaluated_value]
    (super .ctor! 'base_value)  # Pass quoted symbol to macro parent
    (/derived_value = evaluated_value)
  )
)

(var obj (new Derived "actual_value"))  # Should succeed
```

### Requirement: Super Constructor Argument Passing
Super constructor calls SHALL correctly pass arguments (evaluated or unevaluated) based on type.

#### Scenario: Multiple arguments to macro super constructor
**WHEN** calling `(super .ctor!)` with multiple arguments
**THEN** all arguments SHALL be passed unevaluated to the parent constructor
**AND** the parent can choose which to evaluate.

```gene
(class Base
  (.ctor! [arg1 arg2 arg3]
    (/val1 = ($caller_eval arg1))
    (/val2 = arg2)      # Keep unevaluated
    (/val3 = ($caller_eval arg3))
  )
)

(class Derived < Base
  (.ctor! [a b c d]
    (super .ctor! a b c)  # Pass a,b,c unevaluated
    (/val4 = ($caller_eval d))
  )
)

(var obj (new! Derived x y z w))  # Should succeed with proper argument handling
```

### Requirement: Super Constructor Error Context
Super constructor error messages SHALL include parent class information.

#### Scenario: Clear error message with parent class name
**WHEN** there is a super constructor type mismatch
**THEN** the error message SHALL include the parent class name
**AND** SHALL provide clear guidance on the correct syntax.

```gene
(class ConfigurationManager
  (.ctor! [config_file]
    (/config = ($caller_eval config_file))
  )
)

(class ExtendedConfig < ConfigurationManager
  (.ctor [file_name]
    (super .ctor file_name)  # ERROR: Wrong super call type
  )
)

# Expected error: "Super constructor mismatch: Parent class 'ConfigurationManager' has a macro constructor, use '(super .ctor!)' instead of '(super .ctor)'"
```

### Requirement: Deep Inheritance Chains
Super constructor validation SHALL work through multiple inheritance levels.

#### Scenario: Three-level inheritance with macro constructors
**WHEN** there are multiple levels of inheritance with macro constructors
**AND** each level properly calls `(super .ctor!)`
**THEN** the entire chain SHALL work correctly.

```gene
(class GrandParent
  (.ctor! [base_config]
    (/base = ($caller_eval base_config))
  )
)

(class Parent < GrandParent
  (.ctor! [parent_config]
    (super .ctor! parent_config)
    (/parent = ($caller_eval parent_config))
  )
)

(class Child < Parent
  (.ctor! [child_config]
    (super .ctor! child_config)
    (/child = ($caller_eval child_config))
  )
)

(var obj (new! Child config_symbol))  # Should succeed through entire chain
```

### Requirement: Backward Compatibility
Existing `(super .ctor)` calls SHALL continue to work unchanged.

#### Scenario: Existing inheritance patterns
**WHEN** existing code uses regular constructors and `(super .ctor)`
**THEN** the code SHALL continue to work unchanged.

```gene
(class Animal
  (.ctor [name age]
    (/name = name)
    (/age = age)
  )
)

(class Dog < Animal
  (.ctor [name age breed]
    (super .ctor name age)  # Should continue to work
    (/breed = breed)
  )
)

(var dog (new Dog "Buddy" 5 "Golden Retriever"))  # Should continue to work
```