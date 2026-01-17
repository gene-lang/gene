# Pipe Command Specification

## Overview

The `gene pipe` command enables line-by-line stream processing in Unix pipelines. It reads stdin one line at a time, executes Gene code with each line available as `$line`, and prints results to stdout.

---

## ADDED Requirements

### Requirement: CLI Interface

The `pipe` command SHALL be registered with the command manager and accessible via `gene pipe <code>`.

#### Scenario: Basic invocation
```bash
echo "hello" | gene pipe '($line .upper)'
# Output: HELLO
```

#### Scenario: Code as argument
```bash
gene pipe '(+ $line 10)' <<< "5"
# Output: 15
```

---

### Requirement: Line Processing

The command SHALL read stdin line-by-line until EOF, executing the provided code once per line.

#### Scenario: Multiple lines processed independently
```bash
echo -e "1\n2\n3" | gene pipe '(* $line 2)'
# Output:
# 2
# 4
# 6
```

#### Scenario: Empty lines are preserved
```bash
echo -e "a\n\nb" | gene pipe '$line'
# Output:
# a
#
# b
```

---

### Requirement: Special Variable $line

Each input line SHALL be available as a string in the special variable `$line` during code execution.

#### Scenario: Accessing current line
```bash
echo "test" | gene pipe '($line .length)'
# Output: 4
```

#### Scenario: $line contains full line including whitespace
```bash
echo "  spaced  " | gene pipe '$line'
# Output:   spaced
```

---

### Requirement: Result Output

The result of each code execution SHALL be printed to stdout using Gene's standard value representation.

#### Scenario: String results print as-is
```bash
echo "data" | gene pipe '#"Prefix: #{$line}"'
# Output: Prefix: data
```

#### Scenario: Non-string results use Gene representation
```bash
echo "x" | gene pipe '[1 2 3]'
# Output: [1 2 3]
```

#### Scenario: Nil results produce no output (filtering)
```bash
echo -e "keep\nskip\nkeep" | gene pipe '(if ($line == "keep") $line)'
# Output:
# keep
# keep
```

---

### Requirement: Error Handling

The command SHALL exit with non-zero status code on the first error and print error message to stderr.

#### Scenario: Error stops processing
```bash
echo -e "1\nbad\n3" | gene pipe '($line .to_i)'
# Stderr: Error at line 2: ...
# Exit code: 1
# (line 3 is never processed)
```

#### Scenario: Error message includes line number
```bash
echo -e "ok\nerror" | gene pipe '(throw "failed")' 2>&1 | grep "line 2"
# Should match line number in error
```

---

### Requirement: Option Compatibility

The pipe command SHALL support `--debug`, `--trace`, and `--compile` options consistent with `gene eval`.

#### Scenario: Debug flag shows verbose output
```bash
echo "test" | gene pipe --debug '$line' 2>&1 | grep -i "debug"
# Should show debug information on stderr
```

#### Scenario: Trace flag shows execution trace
```bash
echo "x" | gene pipe --trace '(+ 1 1)' 2>&1 | grep -i "trace"
# Should show execution trace on stderr
```

---

### Requirement: Performance & Streaming

The command SHALL process lines in streaming fashion without buffering entire stdin into memory.

#### Scenario: Large file processing (implicit validation)
```bash
# This requirement is validated by implementation design:
# - Read line-by-line using stdin.readLine()
# - Process and output immediately
# - No array accumulation of all lines
```

---

## Usage Examples

### Text transformation
```bash
cat names.txt | gene pipe '($line .upper)'
```

### Filtering
```bash
grep ERROR app.log | gene pipe '(if ($line .contains "CRITICAL") $line)'
```

### JSON line processing
```bash
cat data.jsonl | gene pipe '(var obj (gene/json/parse $line)) obj/name'
```

### Numbering lines
```bash
# Note: This example shows limitation - no built-in line counter
# Users would need to track externally or use awk
cat file.txt | gene pipe '#"#{$line}"'
```

---

## Implementation Notes

1. **Command Module**: Create `src/commands/pipe.nim` following the pattern of `eval.nim`
2. **Line Variable**: Use `set_line_variable()` helper to inject `$line` into namespaces
3. **Compilation**: Compile code once before loop, execute per line for efficiency
4. **Error Context**: Track line number for error reporting
5. **Nil Handling**: Check result kind, skip output if `VkNil`

---

## Non-Requirements

The following are explicitly NOT part of this specification:

- **Line numbers**: No `$line_num` or `$NR` variable (can be added in future if needed)
- **Field splitting**: No automatic `$1`, `$2` field variables like awk (use `($line .split)` explicitly)
- **BEGIN/END blocks**: No special initialization or finalization code blocks
- **Multiple files**: Only stdin is processed (use shell constructs for multiple files)
- **Binary data**: Only text line processing (use `gene eval` for binary stdin)
