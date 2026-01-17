## Why

Unix pipelines are a fundamental pattern for data processing, but Gene currently lacks a dedicated command for line-by-line stream processing. Users must either:
1. Read all stdin into memory with `gene eval` (inefficient for large streams)
2. Write wrapper scripts in shell/awk/perl (defeats the purpose of using Gene)
3. Use multi-line Gene programs with manual stdin loops (verbose)

A `gene pipe` command enables idiomatic stream processing where each input line is processed independently, making Gene a natural fit for Unix pipeline workflows.

## What Changes

- Add a new `gene pipe` command that reads stdin line-by-line and executes Gene code for each line
- Make the current line available as a special variable `$line` (similar to `$args`, `$program`, `$env`)
- Execute code once per input line with fresh variable `$line` each iteration
- Print the result of each evaluation to stdout (auto-formatted like `gene eval`)
- Stop processing and exit with non-zero code on first error
- Support all standard `eval` options (--debug, --trace, etc.) for consistency

## Impact

- **Enables stream processing**: `cat file.txt | gene pipe '($line .upper)'`
- **Filtering**: `grep ERROR logs.txt | gene pipe '(if ($line .contains "CRITICAL") $line)'`
- **Transformation**: `ls | gene pipe '#"File: #{$line}"'`
- **Structured parsing**: `gene pipe '(gene/json/parse $line)' < data.jsonl`
- **No breaking changes**: New command, no modifications to existing commands
- **Minimal implementation**: Reuses existing eval infrastructure, adds line iteration wrapper
