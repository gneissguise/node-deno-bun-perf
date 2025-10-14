#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- Configuration ---
## Defaults
CONNECTIONS=25
DURATION=15
PIPELINING=5
## Custom
#CONNECTIONS=10
#DURATION=4
#PIPELINING=1
RESULTS_DIR="results"
LOG_DIR="${RESULTS_DIR}/logs"
mkdir -p "$RESULTS_DIR" "$LOG_DIR"

# --- Added: dependency checks ---
required_bins=(docker docker-compose autocannon jq curl shuf node deno bun)
for b in "${required_bins[@]}"; do
	if ! command -v "$b" >/dev/null 2>&1; then
		echo "Missing required CLI: $b" >&2
		exit 1
	fi
done

# --- Cleanup Function ---
cleanup() {
    echo ""
    echo "--- Cleaning up background processes and stopping database... ---"
    for pidvar in NODE_PID DENO_PID BUN_PID; do
        if [ -n "${!pidvar-}" ] && kill -0 "${!pidvar}" 2>/dev/null; then
            echo "Killing ${pidvar} (${!pidvar})..."
            kill "${!pidvar}" 2>/dev/null || true
            wait "${!pidvar}" 2>/dev/null || true
        fi
    done
    docker-compose down -v --remove-orphans -t 1 &>/dev/null || true
}
trap cleanup EXIT

# --- Robust healthcheck function (accept 2xx-4xx) ---
wait_for_health() {
	local url=$1
	local timeout=${2:-30}
	local start=$(date +%s)
	printf "Waiting for %s (timeout %ss)...\n" "$url" "$timeout"
	while :; do
		http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$url" || echo "000")
		if [[ "$http_code" =~ ^[234] ]]; then
			printf "Service %s is up (status %s)\n" "$url" "$http_code"
			return 0
		fi
		now=$(date +%s)
		if (( now - start > timeout )); then
			printf "Timeout waiting for %s (last status %s)\n" "$url" "$http_code" >&2
			return 1
		fi
		sleep 0.5
	done
}

# --- Memory sampling helper (polls pid and records RSS in KB) ---
sample_memory_while_running() {
    local pid=$1
    local out_file=$2
    local interval=${3:-0.2}
    # empty file
    : > "$out_file"
    # Poll while PID exists
    while kill -0 "$pid" 2>/dev/null; do
        if [ -r "/proc/$pid/status" ]; then
            rss_kb=$(awk '/VmRSS:/ {print $2}' /proc/"$pid"/status 2>/dev/null || echo 0)
        else
            # portable fallback (may be less precise)
            rss_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)
        fi
        echo "$rss_kb" >> "$out_file"
        sleep "$interval"
    done
}

# --- Helper function to run a single autocannon test ---
# Args: server_name port test_name method path_or_empty
run_test() {
    local server_name=$1
    local port=$2
    local test_name=$3
    local method=$4
    local path=$5
    local result_file="${RESULTS_DIR}/${server_name}_${test_name}.json"

    # Generate dynamic path/body for random tests
    local autocannon_url
    local body_args=()
    local headers_args=()

    if [[ "$test_name" == "random_read" ]]; then
        # pick one random question id for this autocannon run
        local random_id
        random_id=$(shuf -i 1-50 -n 1)
        autocannon_url="http://localhost:${port}/questions/${random_id}"
    else
        autocannon_url="http://localhost:${port}${path}"
    fi

    if [[ "$test_name" == "random_write" ]]; then
        local random_q_id
        random_q_id=$(shuf -i 1-50 -n 1)
        local random_o_id=$(( (random_q_id - 1) * 4 + 1 + (RANDOM % 4) ))
        local body="{\"questionId\":${random_q_id},\"optionId\":${random_o_id}}"
        body_args=(--body "$body")
        headers_args=(-H "Content-Type: application/json")
    fi

    echo ""
    echo "--> Running ${server_name} | ${test_name} -> ${autocannon_url}"
    echo "    connections=${CONNECTIONS} duration=${DURATION}s pipelining=${PIPELINING}"
    echo "    (autocannon output will be saved to ${result_file})"

    # --- Start memory sampler for this server (if PID available) ---
    local pidvar="$(echo "$server_name" | tr '[:lower:]' '[:upper:]')_PID"
    local server_pid=${!pidvar-}
    local mem_log="${RESULTS_DIR}/${server_name}_${test_name}_mem.log"
    local mem_peak_file="${RESULTS_DIR}/${server_name}_${test_name}_mem_peak_kb"
    SAMPLER_PID=""
    if [ -n "${server_pid:-}" ]; then
        # start sampler in background
        sample_memory_while_running "$server_pid" "$mem_log" 0.2 &
        SAMPLER_PID=$!
    fi

    # --- Determine pipelining to use (disable for Bun) ---
    local local_pipelining="$PIPELINING"
    if [[ "$server_name" == "bun" ]]; then
        # Many Bun servers (Fetch API) are observed to behave poorly with HTTP/1.1 pipelining.
        # Disable pipelining for Bun runs to get reliable autocannon results.
        local_pipelining=1
    fi

    # Run autocannon and capture JSON
    autocannon \
        --json \
        --connections "$CONNECTIONS" \
        --duration "$DURATION" \
        --pipelining "$local_pipelining" \
        --method "$method" \
        "${headers_args[@]}" \
        "${body_args[@]}" \
        "$autocannon_url" > "$result_file"

    # stop sampler (sampler exits automatically when PID dies; ensure we kill if still running)
    if [ -n "${SAMPLER_PID}" ]; then
        kill "$SAMPLER_PID" 2>/dev/null || true
        wait "$SAMPLER_PID" 2>/dev/null || true
    fi

    # Compute peak RSS (KB) from mem_log (0 if missing)
    if [ -f "$mem_log" ]; then
        peak=$(awk 'BEGIN{m=0} { if ($1+0>m) m=$1 } END{print m+0}' "$mem_log" 2>/dev/null || echo 0)
    else
        peak=0
    fi
    echo "$peak" > "$mem_peak_file"

    # Print short summary (be tolerant of jq failures)
    echo "    - Requests/sec: $(jq -r '.requests.mean' < "$result_file" 2>/dev/null || echo 'N/A')"
    echo "    - Latency (avg): $(jq -r '.latency.mean' < "$result_file" 2>/dev/null || echo 'N/A') ms"
    echo "    - Throughput: $(jq -r '.throughput.mean' < "$result_file" 2>/dev/null || echo 'N/A')"
    echo "    - Errors: $(jq -r '.errors' < "$result_file" 2>/dev/null || echo 'N/A')"
    echo "    - Peak RSS (KB): ${peak}"
    echo ""
}

# --- Main Execution ---
echo "================================================="
echo "  Ultimate Performance Test: Node vs Deno vs Bun "
echo "================================================="
echo ""
echo "--- Starting PostgreSQL container... ---"
docker-compose up -d --wait
echo "Database container is healthy and ready."

# --- Ensure servers pick up pool size that matches benchmark connections ---
# Export DB_POOL so src/* pick it up when constructing their DB pools.
# Cap per-server pool to avoid exhausting Postgres max_connections when running concurrent load.
# NOTE: Set this so (NUM_SERVERS * MAX_DB_POOL_PER_SERVER) <= Postgres max_connections (default ~100).
MAX_DB_POOL_PER_SERVER=30
if (( CONNECTIONS < MAX_DB_POOL_PER_SERVER )); then
  export DB_POOL="${CONNECTIONS}"
else
  export DB_POOL="${MAX_DB_POOL_PER_SERVER}"
fi
echo "Exported DB_POOL=$DB_POOL (capped to ${MAX_DB_POOL_PER_SERVER})"

echo "--- Test Parameters ---"
echo "Connections: $CONNECTIONS | Duration: ${DURATION}s | Pipelining: $PIPELINING"
echo ""

# --- Start DB (ensure logs availa
# The Ultimate Performance Test: Node vs Deno vs Bun
# with a realistic, high-traffic, mixed read/write workload.ble) ---
docker-compose up -d postgres
sleep 2
docker-compose logs --no-color postgres | tail -n +1 || true

# --- Start servers (redirect logs) ---
echo "Starting servers (node/deno/bun)... logs -> $LOG_DIR"
nohup node src/node_quiz_api.js > "$LOG_DIR/node.log" 2>&1 &
NODE_PID=$!
nohup deno run --allow-net --allow-env src/deno_quiz_api.js > "$LOG_DIR/deno.log" 2>&1 &
DENO_PID=$!
nohup bun run src/bun_quiz_api.js > "$LOG_DIR/bun.log" 2>&1 &
BUN_PID=$!
echo "Node PID: $NODE_PID  Deno PID: $DENO_PID  Bun PID: $BUN_PID"

# --- Wait for health on each server ---
wait_for_health "http://localhost:3000/healthcheck" 40
wait_for_health "http://localhost:3001/healthcheck" 40
wait_for_health "http://localhost:3002/healthcheck" 40

# --- Run benchmarks (autocannon) ---
echo ""
echo "--- Benchmarking Node.js (Express) on port 3000 ---"
run_test "node" 3000 "heavy_read" "GET" "/questions"
run_test "node" 3000 "random_read" "GET" ""          # random_read uses internal shuf to pick target
run_test "node" 3000 "random_write" "POST" "/answers"
kill $NODE_PID || true
wait $NODE_PID 2>/dev/null || true
echo "-------------------------------------------------"

echo "--- Benchmarking Deno on port 3001 ---"
run_test "deno" 3001 "heavy_read" "GET" "/questions"
run_test "deno" 3001 "random_read" "GET" ""
run_test "deno" 3001 "random_write" "POST" "/answers"
kill $DENO_PID || true
wait $DENO_PID 2>/dev/null || true
echo "-------------------------------------------------"

echo "--- Benchmarking Bun on port 3002 ---"
run_test "bun" 3002 "heavy_read" "GET" "/questions"
run_test "bun" 3002 "random_read" "GET" ""
run_test "bun" 3002 "random_write" "POST" "/answers"

# --- Added: diagnostics for Bun failures ---
# If Bun results show 0 requests or non-zero errors, dump recent bun log + JSON for debugging.
for f in "${RESULTS_DIR}/bun_"*.json; do
  if [ -f "$f" ]; then
    errs=$(jq -r '.errors' < "$f" 2>/dev/null || echo "0")
    reqs=$(jq -r '.requests.total' < "$f" 2>/dev/null || echo "0")
    if [ "$reqs" = "0" ] || { [ "$errs" != "0" ] && [ "$errs" != "null" ]; }; then
      echo ""
      echo "=== Bun diagnostic: ${f} shows requests=${reqs}, errors=${errs} ==="
      echo "----- Tail of Bun server log ($LOG_DIR/bun.log) -----"
      tail -n 200 "$LOG_DIR/bun.log" || true
      echo "----- Contents of ${f} -----"
      cat "$f" || true
      echo "===================================================="
    fi
  fi
done

kill $BUN_PID || true
wait $BUN_PID 2>/dev/null || true
echo "-------------------------------------------------"

echo "Benchmark complete. Raw JSON results are in the '${RESULTS_DIR}' directory."
echo "-------------------------------------------------"

# --- Add: aggregated summary (per-category, fastest->slowest and mem asc->desc) ---
# Categories to summarize
CATS=(heavy_read random_read random_write)
SERVERS=(node deno bun)

echo ""
echo "================== BENCHMARK SUMMARY =================="
for cat in "${CATS[@]}"; do
  echo ""
  echo "Category: $cat"
  # Build CSV lines: server,req_mean,latency_mean,throughput_mean,mem_kb
  tmpfile=$(mktemp)
  for s in "${SERVERS[@]}"; do
    jf="${RESULTS_DIR}/${s}_${cat}.json"
    mf="${RESULTS_DIR}/${s}_${cat}_mem_peak_kb"
    req=$(jq -r '.requests.mean // 0' < "$jf" 2>/dev/null || echo 0)
    lat=$(jq -r '.latency.mean // 0' < "$jf" 2>/dev/null || echo 0)
    thr=$(jq -r '.throughput.mean // 0' < "$jf" 2>/dev/null || echo 0)
    mem=$(cat "$mf" 2>/dev/null || echo 0)
    # ensure numeric fallback
    req=${req:-0}; lat=${lat:-0}; thr=${thr:-0}; mem=${mem:-0}
    # print CSV (server,req,lat,thr,mem)
    printf "%s,%s,%s,%s,%s\n" "$s" "$req" "$lat" "$thr" "$mem" >> "$tmpfile"
  done

  echo "  Fastest -> Slowest (by requests/sec):"
  printf "    %-6s %-12s %-12s %-12s %-10s\n" "Rank" "Server" "Req/sec" "Latency(ms)" "Mem(KB)"
  sort -t',' -k2 -nr "$tmpfile" | awk -F',' 'BEGIN{rank=1} {printf "    %-6d %-12s %-12s %-12s %-10s\n", rank, $1, $2, $3, $5; rank++}'
  echo ""
  echo "  Least -> Most memory (by peak RSS KB):"
  printf "    %-6s %-12s %-12s %-12s %-10s\n" "Rank" "Server" "Mem(KB)" "Req/sec" "Latency(ms)"
  sort -t',' -k5 -n "$tmpfile" | awk -F',' 'BEGIN{rank=1} {printf "    %-6d %-12s %-12s %-12s %-10s\n", rank, $1, $5, $2, $3; rank++}'
  rm -f "$tmpfile"
done
echo "======================================================="
echo ""

