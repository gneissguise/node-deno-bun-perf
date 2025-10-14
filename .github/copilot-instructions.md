# Quick context

This repo benchmarks Node.js, Deno, and Bun implementations of the same Quiz API backed by a single PostgreSQL instance. The goal is to run realistic high-concurrency read/write workloads (autocannon) against three language runtimes and collect JSON results under `results/`.

This file documents the current runflow, important changes, and troubleshooting tips.

---

## Big-picture architecture

- Single PostgreSQL database provisioned by `docker-compose.yml` (service: `postgres`, DB: `quiz_db`, user: `quiz_user`). `init.sql` seeds 50 questions + options.
- Three HTTP servers (same API, ports shown):
  - `src/node_quiz_api.js` — Express + `pg` (port 3000)
  - `src/deno_quiz_api.js` — Deno + `postgres` (port 3001)
  - `src/bun_quiz_api.js` — Bun; prefers `postgres` (postgres.js) and falls back to `pg` when necessary (port 3002)
- Benchmark driver: `run_benchmark.sh` — starts DB, launches servers, waits for health, runs three autocannon workloads per server, saves JSON under `results/` and samples memory usage.

Key recent improvements:
- `run_benchmark_debug.sh` for verbose per-request curl debugging.
- `run_benchmark.sh` now:
  - Exports DB_POOL (capped) so servers use appropriate pool sizes.
  - Samples server RSS during runs and saves peak memory samples.
  - Emits a sorted summary (fastest → slowest, least → most mem).
  - Provides Bun diagnostics when autocannon results look empty.
- Bun server (`src/bun_quiz_api.js`) now uses a safe DB layer:
  - Prefers `postgres` (postgres.js) in Bun (native).
  - Falls back to `pg` only if necessary (tagged-template compatibility kept).
  - Adds per-query timeout (env var: BUN_DB_QUERY_TIMEOUT_MS, default 5000ms) to avoid hanging DB calls under load.

---

## Files & responsibilities

- run_benchmark.sh — primary orchestration and performance runs (autocannon). Edit CONNECTIONS / DURATION / PIPELINING here.
- run_benchmark_debug.sh — verbose curl-based debugging routine (per-request full HTTP trace).
- src/node_quiz_api.js — Node implementation. Uses DB_POOL env var if set.
- src/deno_quiz_api.js — Deno implementation. Uses DB_POOL env var if set.
- src/bun_quiz_api.js — Bun implementation. Uses DB_POOL, prefers postgres.js; supports BUN_DB_QUERY_TIMEOUT_MS.
- docker-compose.yml — PostgreSQL service and init script mount.
- init.sql — schema + seed data (50 questions). Avoid changing unless you intend to change the seeded dataset.
- results/ — output directory (ignored by git). Contains autocannon JSON and memory logs.

Developer helper scripts (optional)
- request_generators.js — example autocannon generators (not used by current scripts by default).
- response_inspector.js — helper to inspect non-2xx responses (not used by current scripts by default).
  - These can be removed if you prefer a minimal repo; `run_benchmark*.sh` do not require them.

---

## Running locally

Requirements: docker, docker-compose, node, deno, bun, autocannon, jq, curl, shuf.

Start DB only:
- docker-compose up -d

Run the full performance benchmark:
- ./run_benchmark.sh

Verbose request debugging (per-server, per-request curl):
- ./run_benchmark_debug.sh

Run a single server for debugging:
- Node: node src/node_quiz_api.js
- Deno: deno run --allow-net --allow-env src/deno_quiz_api.js
- Bun: bun run src/bun_quiz_api.js

Environment variables useful for runs:
- DB_POOL — per-server DB pool size (exported by run_benchmark.sh to match CONNECTIONS; capped).
- BUN_DB_QUERY_TIMEOUT_MS — per-query timeout (ms) used by Bun (default 5000).

---

## Troubleshooting checklist

1. Healthcheck
   - Verify /healthcheck fast 200 on ports 3000/3001/3002:
     - curl -i http://localhost:3000/healthcheck
(updated)
2. DB connections / pool sizing
   - Ensure Postgres max_connections in docker-compose.yml >= sum of server pools + DB admin connections.
   - If autocannon shows lots of errors or 0 responses for a server, reduce DB_POOL or increase Postgres max_connections.

3. Bun-specific
   - Prefer installing `postgres` in Bun: `bun add postgres`. The server code prefers `postgres` and uses `pg` fallback only if needed.
   - If Bun appears to hang or autocannon reports zero successful requests:
     - Check `results/logs/bun.log` for DB errors and connection timeouts.
     - Adjust BUN_DB_QUERY_TIMEOUT_MS to a higher value in the environment if DB is slow.

4. Inspect logs
   - Results & logs are under `results/` (autocannon JSON, mem logs) and `results/logs/*.log` (server logs).
   - Check `results/logs/<server>.log` and docker-compose logs for Postgres.

5. Reproducing failures
   - Use run_benchmark_debug.sh to get full HTTP request/response traces for failing endpoints before attempting large autocannon runs.

---

## Best practices & notes

- Keep API shapes stable. The benchmark relies on endpoints: GET /questions, GET /questions/:id, POST /answers (JSON {questionId, optionId}).
- Use status codes (200/201/400/404/500) in assertions, not textual responses.
- When increasing CONNECTIONS, update DB_POOL and ensure Postgres max_connections is sufficient.
- `results/` is gitignored; keep raw outputs locally for analysis.

---

If you want, I can:
- Remove unused helper files (request_generators.js, response_inspector.js) and produce a small commit.
- Add CI job examples that run the benchmark in a CI-friendly reduced-load mode.
- Bump docker-compose Postgres max_connections if you plan to increase CONNECTIONS beyond current caps.
