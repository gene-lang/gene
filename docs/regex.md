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

- `match` → `RegexpMatch` or `nil`
- `process` → compatibility alias for `match`
- `find` → first matched substring or `nil`
- `find_all` → array of matched substrings
- `split` → split input by regex
- `scan` → array of non-overlapping matches
- `replace` → replace first match
- `replace_all` → replace all matches
- `sub` / `gsub` → aliases for `replace` / `replace_all`

`RegexpMatch` exposes:

- `value`
- `captures`
- `named_captures`
- `start`
- `end`
- `pre_match`
- `post_match`

`start` and `end` use UTF-8 character offsets, with `end` exclusive.

Replacement strings accept numeric backrefs (`\1`, `\2`, ...) and named
backrefs (`\k<name>` / `\g<name>`). If no replacement argument is supplied,
`replace`/`replace_all` use the replacement stored on the Regexp instance or
literal; if none is available, they raise an error.

## String Helpers

`String` provides the following regex-aware helpers:

- `match` — **requires** a `Regexp`
- `contain` — boolean helper that accepts a `Regexp` or string pattern
- `split`, `find`, `find_all`, `scan`, `replace`, `replace_all`, `sub`, `gsub`
  — accept a `Regexp` or a string pattern where documented

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
- Named captures and named backrefs are supported for the common PCRE forms
  `(?<name>...)`, `(?'name'...)`, and `(?P<name>...)`.

For the broader design direction around UTF-8 strings, `CString` FFI, and
Ruby-inspired `String`/`Regexp` behavior, see
[string_regex_design.md](string_regex_design.md).
