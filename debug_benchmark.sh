#!/usr/bin/env bash
#  - waits for /healthcheck on each
#  - runs: 1 heavy read, 5 random reads, 1 random write per server
#  - prints full verbose request+response for every curl (-v)
#
# Usage: ./debug_benchmark.sh

# --- Configuration ---
NUM_RANDOM_READS=5
HEAVY_READS=1
NUM_WRITES=1
# Ports for servers: node, deno, bun
PORTS=(3000 3001 3002)
LOG_DIR="results/logs"
NUM_START_WAIT=30

# --- Prerequisites check ---
required_bins=(docker docker-compose curl node deno bun)
for bin in "${required_bins[@]}"; do
	if ! command -v "$bin" >/dev/null 2>&1; then
		echo "ERROR: Missing required CLI: $bin" >&2
		exit 1
	fi
done

# --- Cleanup Function ---
cleanup() {
	echo ""
	echo "--- Cleaning up background processes and stopping database... ---"
	# Kill servers if running
	for pidvar in NODE_PID DENO_PID BUN_PID; do
		if [ -n "${!pidvar-}" ] && kill -0 "${!pidvar}" 2>/dev/null; then
			echo "Killing ${pidvar} (${!pidvar})..."
			kill "${!pidvar}" 2>/dev/null || true
			wait "${!pidvar}" 2>/dev/null || true
		fi
	done
	# Bring down docker-compose (remove volumes to ensure clean DB next run)
	if command -v docker-compose >/dev/null 2>&1; then
		docker-compose down -v --remove-orphans || true
	fi
}
trap cleanup EXIT

# --- Helper to wait for a server to be ready (accept 2xx-4xx) ---
wait_for_server() {
	local port=$1
	local timeout=${2:-$NUM_START_WAIT}
	local start_ts=$(date +%s)
	printf "Waiting for server on port %s (timeout %ss)...\n" "$port" "$timeout"
	while :; do
		http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:${port}/healthcheck" || echo "000")
		if [[ "$http_code" =~ ^[234] ]]; then
			printf "Server on port %s is up (status %s)\n" "$port" "$http_code"
			return 0
		fi
		now_ts=$(date +%s)
		if (( now_ts - start_ts > timeout )); then
			printf "ERROR: timeout waiting for server on port %s (last status %s)\n" "$port" "$http_code" >&2
			return 1
		fi
		sleep 0.5
	done
}

# --- Run a curl test (verbose) ---
# args: port method path repeat_count [curl_extra_args...]
run_curl_test() {
	local port=$1; shift
	local method=$1; shift
	local path=$1; shift
	local repeats=$1; shift
	local curl_args=("$@")

	for i in $(seq 1 "$repeats"); do
		echo ""
		echo "==============================================="
		echo "Server: http://localhost:${port} | Test: ${method} ${path} | Attempt #${i}"
		echo "Full HTTP request and response will be shown below (curl -v)."
		echo "-----------------------------------------------"
		# Use -v to show request and response (headers and body)
		# Use --max-time to avoid hanging connections
		curl -v --max-time 10 -X "$method" "${curl_args[@]}" "http://localhost:${port}${path}"
		echo ""
		echo "-----------------------------------------------"
		sleep 0.2
	done
	echo "==============================================="
}

# --- Start DB ---
echo "Starting PostgreSQL container via docker-compose..."
docker-compose up -d
echo "Waiting a few seconds for DB init scripts to run..."
sleep 3
echo "docker-compose logs postgres (tail)"
docker-compose logs --no-color postgres | tail -n 200 || true
echo ""

# Ensure log dir
mkdir -p "$LOG_DIR"

# --- Start servers ---
echo "Starting Node.js server (port 3000)..."
nohup node src/node_quiz_api.js > "$LOG_DIR/node.log" 2>&1 &
NODE_PID=$!
echo "Node PID: $NODE_PID"

echo "Starting Deno server (port 3001)..."
nohup deno run --allow-net --allow-env src/deno_quiz_api.js > "$LOG_DIR/deno.log" 2>&1 &
DENO_PID=$!
echo "Deno PID: $DENO_PID"

echo "Starting Bun server (port 3002)..."
nohup bun run src/bun_quiz_api.js > "$LOG_DIR/bun.log" 2>&1 &
BUN_PID=$!
echo "Bun PID: $BUN_PID"

echo ""
# Wait for each server healthcheck
for port in "${PORTS[@]}"; do
	if ! wait_for_server "$port" 40; then
		echo "ERROR: Server on port $port failed to become ready. Inspect logs in $LOG_DIR." >&2
		exit 1
	fi
done

echo ""
echo "All servers are ready. Beginning verbose debug routines."
echo "Note: Each request will show full HTTP request and response (curl -v). Logs are saved to $LOG_DIR."

# --- Per-server test sequence ---
for port in "${PORTS[@]}"; do
	echo ""
	echo "=========================================================="
	echo "DEBUG ROUTINE for server on port $port"
	echo "=========================================================="

	# 1) Heavy read: GET /questions (run once)
	echo ""
	echo ">> Heavy read: GET /questions (once)"
	run_curl_test "$port" "GET" "/questions" "$HEAVY_READS"

	# 2) Random reads: 5 times GET /questions/<1-50>
	echo ""
	echo ">> Random reads: GET /questions/<1-50> (${NUM_RANDOM_READS} times)"
	for r in $(seq 1 "$NUM_RANDOM_READS"); do
		QUESTION_ID=$((1 + (RANDOM % 50)))
		run_curl_test "$port" "GET" "/questions/${QUESTION_ID}" 1
	done

	# 3) Random write: POST /answers (once)
	echo ""
	echo ">> Random write: POST /answers (once)"
	QUESTION_ID=$((1 + (RANDOM % 50)))
	OPTION_ID=$(( (QUESTION_ID - 1) * 4 + 1 + (RANDOM % 4) ))
	DATA_PAYLOAD="{\"questionId\": ${QUESTION_ID}, \"optionId\": ${OPTION_ID}}"
	# Build curl args for JSON body
	CURL_JSON_ARGS=(-H "Content-Type: application/json" -d "${DATA_PAYLOAD}")
	run_curl_test "$port" "POST" "/answers" 1 "${CURL_JSON_ARGS[@]}"
done

echo ""
echo "All debug routines completed. Inspect verbose output above and detailed server logs in $LOG_DIR."
echo "If any server failed, check its log file (node.log / deno.log / bun.log) and postgres logs via docker-compose logs postgres."
echo ""

