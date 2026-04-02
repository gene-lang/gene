## MODIFIED Requirements

### Requirement: Represent Effects In Function Type Expressions
The system SHALL parse effect lists inside canonical `Fn` type expressions written as `(Fn ! [Effects])`, `(Fn [Args] ! [Effects])`, `(Fn -> Return ! [Effects])`, or `(Fn [Args] -> Return ! [Effects])`.

#### Scenario: Effectful function type in an annotation
- **WHEN** a parameter is annotated with `(Fn [Int] -> Int ! [Db])`
- **THEN** the parameter's type includes the `Db` effect
