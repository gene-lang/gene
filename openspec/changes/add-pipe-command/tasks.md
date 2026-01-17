## 1. Command Infrastructure

- [ ] 1.1 Create `src/commands/pipe.nim` module implementing the pipe command handler
- [ ] 1.2 Register the `pipe` command in `src/gene.nim` command manager
- [ ] 1.3 Add command help text describing usage and options

## 2. Line Processing Loop

- [ ] 2.1 Implement stdin line-by-line reader that processes until EOF
- [ ] 2.2 Set `$line` variable in global namespace before each code execution
- [ ] 2.3 Execute compiled Gene code once per input line with fresh `$line` value
- [ ] 2.4 Print result to stdout after each line execution (using `$result` representation)
- [ ] 2.5 Handle nil results (skip output for nil to enable filtering)

## 3. Error Handling

- [ ] 3.1 Catch Gene exceptions during line processing
- [ ] 3.2 Exit with non-zero status code on first error
- [ ] 3.3 Print error message to stderr with line number context

## 4. Special Variable Support

- [ ] 4.1 Add `set_line_variable(line: string)` helper in `src/gene/types/helpers.nim`
- [ ] 4.2 Make `$line` accessible similar to `$args`, `$program`, `$env`
- [ ] 4.3 Ensure `$line` is available in both global and gene namespaces

## 5. Option Support

- [ ] 5.1 Support `--debug` flag for debug output
- [ ] 5.2 Support `--trace` flag for execution tracing
- [ ] 5.3 Support `--compile` flag to show compilation details
- [ ] 5.4 Ensure consistency with `gene eval` option handling

## 6. Testing & Validation

- [ ] 6.1 Create `testsuite/pipe/` directory for pipe command tests
- [ ] 6.2 Add test: basic line transformation (`echo "hello" | gene pipe '($line .upper)'`)
- [ ] 6.3 Add test: filtering with nil (`echo -e "a\nb\nc" | gene pipe '(if ($line == "b") $line)'`)
- [ ] 6.4 Add test: string interpolation (`echo "world" | gene pipe '#"Hello #{$line}!"'`)
- [ ] 6.5 Add test: error handling (ensure exit code is non-zero on error)
- [ ] 6.6 Add test: multi-line processing (verify each line is processed independently)
- [ ] 6.7 Update CLI help documentation with pipe command examples

## 7. Documentation

- [ ] 7.1 Add usage examples to command help text
- [ ] 7.2 Document `$line` special variable in language documentation
- [ ] 7.3 Add `gene pipe` examples to README or docs/usage.md
