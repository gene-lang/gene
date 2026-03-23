# Gene Standard Library Tests

This directory contains runnable Gene tests for the shipped stdlib surface.

## Layout

Top-level tests in this directory cover broad stdlib areas:

- `1_core_print.gene` — basic print/println behavior
- `2_math_basic.gene` — baseline math helpers
- `3_env_vars.gene` — environment variable helpers
- `4_json_tagged.gene` — tagged Gene JSON round-tripping
- `5_math_advanced.gene` — additional math helpers
- `6_system.gene` — platform/system helpers
- `7_tree_serdes.gene` — tree-based serialization helpers
- `8_runtime_serdes.gene` — runtime serialization/deserialization
- `9_immutable_maps.gene` — immutable map literals
- `10_immutable_genes.gene` — immutable Gene literals

Nested directories cover namespace-focused areas:

- `core/` — core helpers such as `print`, `assert`, and base64
- `arrays/` — array instance methods and immutable arrays
- `strings/` — string helpers and regex integration
- `io/` — file I/O helpers
- `time/` — sleep, now, and duration helpers

## Running

Run the default stdlib section through the main runner:

```bash
cd testsuite
./run_tests.sh
```

Run stdlib tests directly:

```bash
bin/gene run testsuite/14-stdlib/stdlib/8_runtime_serdes.gene
bin/gene run testsuite/14-stdlib/stdlib/strings/2_regex_methods.gene
bin/gene run testsuite/14-stdlib/stdlib/time/1_sleep_and_now.gene
```

## Notes

- `14-stdlib/stdlib/time/` is now part of the default recursive section run.
- `serdes_objects.gene` is a support module for serialization tests, not a standalone test.
- For lower-level stdlib coverage, also see Nim tests under `tests/`, such as JSON, datetime, string, array, regex, process, sqlite, and postgres suites.
