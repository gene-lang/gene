# Benchmarking Gene HTTP Server with Apache Bench

This document shows how to use Apache Bench (`ab`) to benchmark the Gene HTTP server, particularly to test concurrent request handling.

## Prerequisites

Apache Bench comes pre-installed on macOS. On Linux, install it with:

```bash
# Ubuntu/Debian
sudo apt-get install apache2-utils

# CentOS/RHEL
sudo yum install httpd-tools
```

## Starting the Server

Start the concurrent HTTP server:

```bash
# From the gene project root directory
bin/gene run examples/http_concurrent.gene
```

Expected output:
```
Concurrent mode enabled - each request will be handled in a separate thread
HTTP server started on port 8085
Server running on port 8085
...
```

## Basic Benchmarks

### Test Fast Endpoint (/)

```bash
# 100 requests, 10 concurrent
ab -n 50 -c 10 http://127.0.0.1:8085/
```

### Test Slow Endpoint (/slow) - The Real Test

The `/slow` endpoint has a 2-second delay, making it ideal for testing concurrency.

#### Sequential Baseline (1 concurrent)
```bash
# 5 requests, 1 at a time (should take ~10 seconds)
ab -n 5 -c 1 http://127.0.0.1:8085/slow
```

#### Concurrent Test (5 concurrent)
```bash
# 5 requests, all at once (should take ~2-4 seconds if concurrent)
ab -n 5 -c 5 http://127.0.0.1:8085/slow
```

#### Stress Test (more concurrent than threads)
```bash
# 20 requests, 10 concurrent
ab -n 20 -c 10 http://127.0.0.1:8085/slow
```

## Understanding the Output

Key metrics from `ab` output:

```
Concurrency Level:      10           # Number of concurrent requests
Time taken for tests:   4.123 sec    # Total time
Complete requests:      20           # Successful requests
Failed requests:        0            # Errors
Requests per second:    4.85 [#/sec] # Throughput
Time per request:       2061 ms      # Average response time (all concurrent)
Time per request:       206.1 ms     # Average per single request
```

### What to Look For

1. **Time taken for tests**: With concurrent mode:
   - 5 requests with 2-second delay should complete in ~2-4 seconds (not 10)
   - This proves requests are handled in parallel

2. **Failed requests**: Should be 0
   - Non-zero indicates server issues

3. **Requests per second**: Higher is better
   - With 2-second delay: theoretical max is ~0.5 req/sec per thread

## Expected Results

### Without Concurrent Mode (`^concurrent false` or omitted)

```bash
ab -n 5 -c 5 http://127.0.0.1:8086/slow
# Time taken: ~10 seconds (requests handled sequentially)
# Only 1 request processed at a time
```

### With Concurrent Mode (`^concurrent true`)

```bash
ab -n 5 -c 5 http://127.0.0.1:8085/slow
# Time taken: ~2-4 seconds (requests handled in parallel)
# All 5 requests processed simultaneously
```

## Full Benchmark Script

Save as `benchmark.sh`:

```bash
#!/bin/bash

echo "=== Gene HTTP Server Benchmark ==="
echo ""

# Fast endpoint
echo "1. Fast endpoint (/) - 100 requests, 10 concurrent:"
ab -n 100 -c 10 http://127.0.0.1:8085/ 2>&1 | grep -E "(Requests per second|Time taken|Failed)"
echo ""

# Slow endpoint - sequential
echo "2. Slow endpoint (/slow) - 3 requests, 1 concurrent (baseline):"
ab -n 3 -c 1 http://127.0.0.1:8085/slow 2>&1 | grep -E "(Requests per second|Time taken|Failed)"
echo ""

# Slow endpoint - concurrent
echo "3. Slow endpoint (/slow) - 3 requests, 3 concurrent:"
ab -n 3 -c 3 http://127.0.0.1:8085/slow 2>&1 | grep -E "(Requests per second|Time taken|Failed)"
echo ""

# Stress test
echo "4. Stress test (/slow) - 10 requests, 5 concurrent:"
ab -n 10 -c 5 http://127.0.0.1:8085/slow 2>&1 | grep -E "(Requests per second|Time taken|Failed)"
echo ""

echo "=== Benchmark Complete ==="
```

Run with:
```bash
chmod +x benchmark.sh
./benchmark.sh
```

## Alternative: Using `wrk` (Higher Performance)

For more intensive benchmarks, use `wrk`:

```bash
# Install on macOS
brew install wrk

# Benchmark
wrk -t4 -c10 -d10s http://127.0.0.1:8085/
```

## Alternative: Using `curl` for Quick Tests

```bash
# Time 5 parallel requests
time (for i in {1..5}; do curl -s http://127.0.0.1:8085/slow & done; wait)

# Should complete in ~2 seconds with concurrent mode
# Would take ~10 seconds without concurrent mode
```

## Troubleshooting

### "Connection refused"
- Server not running or wrong port

### All requests timeout
- Server might be blocked/deadlocked
- Check server console for errors

### Slow even with concurrent mode
- Thread pool might be exhausted (max 63 concurrent)
- Check for blocking operations in handler

### High failure rate
- Server can't handle the load
- Reduce concurrency level (`-c` option)
