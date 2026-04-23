# Benchmarking The HTTP Server

This document shows how to benchmark the current HTTP example and how to test
the optional concurrent server mode implemented in `genex/http`.

This is an implementation note, not a language-spec document.

## Benchmark The Shipped Example

Start the current example server:

```bash
./bin/gene run examples/http_server.gene
```

It listens on `http://127.0.0.1:8086` and exposes:

- `/` -> plain text response
- `/health` -> JSON response

Basic `ab` checks:

```bash
ab -n 100 -c 10 http://127.0.0.1:8086/
ab -n 100 -c 10 http://127.0.0.1:8086/health
```

For a quick latency sample with `curl`:

```bash
time curl -s http://127.0.0.1:8086/ > /dev/null
time curl -s http://127.0.0.1:8086/health > /dev/null
```

## Benchmark Concurrent Mode

`start_server` supports `^concurrent true` and `^workers <n>`, but the shipped
example does not enable that mode. To test it, use a handler that does enough
work to make overlap visible.

The repo now includes a baseline demo, an actor-backed concurrent variant, and a runner:

```bash
./bin/gene run examples/http_ab_demo.gene
./bin/gene run examples/http_ab_actor_demo.gene
./scripts/bench_http_ab_demo.sh
```

The script benchmarks both servers, waits for `/health`, then runs both:

- a sequential `ab` pass against `/slow`
- a concurrent `ab` pass against `/slow`

Both demos measure end-to-end request/response latency:

- `http_ab_demo.gene` runs the blocking `sleep_ms` directly in the HTTP request path
- `http_ab_actor_demo.gene` sends that same blocking work to a 10-actor worker pool and waits for the reply before responding

Environment overrides:

```bash
REQUESTS=40 CONCURRENCY=8 ./scripts/bench_http_ab_demo.sh
```

Minimal example:

```gene
(import genex/http)

(fn app [req]
  (if (req/path == "/slow")
    (do
      (sleep 2000)
      (respond 200 "slow ok")
    )
  else
    (respond 200 "ok")
  ))

(start_server 8086 app ^concurrent true ^workers 4)
(run_forever)
```

Then compare:

```bash
ab -n 5 -c 1 http://127.0.0.1:8086/slow
ab -n 5 -c 5 http://127.0.0.1:8086/slow
```

The concurrent run should complete materially faster than the sequential one if
the handler work overlaps across workers.

## Notes

- `ab` is fine for quick checks; `wrk` is better for longer runs.
- Benchmark the exact handler shape you care about. The example server is too
  small to say much about real application throughput.
- If the actor-backed demo does not improve front-door latency, verify that it
  called `gene/actor/enable` first and that `GENE_WORKERS` is high enough for
  the requested worker count.
