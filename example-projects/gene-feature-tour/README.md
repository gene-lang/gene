# Gene Feature Tour

This example project is executable documentation for current Gene Stable and Beta surfaces. The default core tour is deterministic and does not require native extensions, network access, a database server, or a long-running HTTP server.

## What is covered

Core tour:

- syntax, literals, primitive values, arrays, maps, and Gene values
- functions, closures, higher-order calls, and macro-like `fn!` functions
- packages, package metadata, and module imports
- standard library examples for strings, regex, JSON, base64, time, arrays, and maps
- enum ADTs, tuple product types, Result/Option, and slash product-data access
- documented pattern matching subset
- selector lookup/default/value/set examples
- gradual typing examples in default nil-compatible mode
- OOP classes, inheritance, interfaces, adapters, and callable instances
- explicit runtime interception
- async futures, callbacks, and bounded actor messaging

Optional extension tours:

- bounded HTTP extension value/status demo
- local SQLite extension demo

## Build Gene

From the repository root:

```sh
nimble build
```

## Run the core tour

The source-tour commands use `--no-gir-cache` so each run executes the current source files and stays path-independent across working directories. GIR/cache inspection is shown separately below.

From the repository root:

```sh
bin/gene run --no-gir-cache example-projects/gene-feature-tour/src/index.gene
```

From this example project directory (`example-projects/gene-feature-tour`):

```sh
../../bin/gene run --no-gir-cache src/index.gene
```

From any other directory, use absolute paths:

```sh
<repo>/bin/gene run --no-gir-cache <repo>/example-projects/gene-feature-tour/src/index.gene
```

Replace `<repo>` with the absolute path to your Gene checkout.

A successful run ends with:

```text
Core feature tour complete
```

## Inspect or compile the core tour

From the repository root:

```sh
bin/gene parse example-projects/gene-feature-tour/src/index.gene
bin/gene compile example-projects/gene-feature-tour/src/index.gene
```

## Build native/custom extensions

Extension demos are optional. Build the native extension libraries before running them.

From this example project directory:

```sh
./scripts/build_extensions.sh
```

The helper prints and runs the repository-root command:

```sh
nimble buildext
```

## Run extension demos

After building extensions, from the repository root:

```sh
bin/gene run --no-gir-cache example-projects/gene-feature-tour/src/extensions/http.gene
bin/gene run --no-gir-cache example-projects/gene-feature-tour/src/extensions/sqlite.gene
```

Or from this example project directory:

```sh
../../bin/gene run --no-gir-cache src/extensions/http.gene
../../bin/gene run --no-gir-cache src/extensions/sqlite.gene
```

The HTTP demo is intentionally bounded: it demonstrates `genex/http` request/response values, JSON parsing, and status diagnostics, but does not start a long-running server. Server lifecycle examples should use a wrapper script that owns startup, smoke test, and cleanup.

The SQLite demo uses a local `/tmp/gene_feature_tour.sqlite` database and exits after printing the queried rows.
