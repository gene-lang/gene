# Regex (Regexp) Support

This document describes the Regexp API and regex literal syntax used by the VM.

## Literal Syntax

- `#/pattern/flags`
- `#/pattern/replacement/flags`

Delimiters:
- Escape a literal `/` as `\/`.
- Escape a literal `\` as `\\`.

Flags:
- `i` — ignore case
- `m` — dot matches newline (PCRE dotall)

Examples:
```gene
#/ab/i
#/(\\d)/[\\1]/
```

## Regexp Construction

Use the `gene/Regexp` class. Flags are passed as properties.

```gene
(var r (new gene/Regexp ^^i ^^m "a.b"))
(var r2 (new gene/Regexp ^^i "(\\d)" "[\\1]"))
```

## Regexp Methods

- `match` → boolean
- `process` → `RegexpMatch` or `nil`
- `find` → first matched substring or `nil`
- `find_all` → array of matched substrings
- `replace` → replace first match
- `replace_all` → replace all matches

Replacement strings accept Ruby-style numeric backrefs (`\1`, `\2`, ...). If no
replacement argument is supplied, `replace`/`replace_all` use the replacement
stored on the Regexp instance or literal; if none is available, they raise an error.

## String Helpers

`String` provides the following regex-aware helpers:

- `match` — **requires** a `Regexp`
- `contain`, `find`, `find_all`, `replace`, `replace_all` — accept a `Regexp` or a
  string pattern (string patterns are treated as literal substrings)

Examples:
```gene
("Hello" .contain #/ELL/i)
("ababa" .find_all "a")
("a1b2" .replace_all #/(\\d)/[\\1]/)
```

## Compatibility Notes

- The VM uses PCRE via Nim's `re` module. This is close to Ruby syntax but not
  identical.
- The `m` flag maps to dotall (`.` matches newline). Anchors (`^`, `$`) follow
  PCRE behavior and may differ from Ruby defaults.
- Named captures and named backrefs are not supported in this iteration.
