#!/bin/bash
# ============================================================
# generate_load.sh — Controlled CPU-heavy workload generator
# ============================================================
# Usage: ./generate_load.sh [INTENSITY] [DURATION_SECONDS]
#   INTENSITY : number of parallel worker processes (default: 1)
#   DURATION  : seconds each worker runs         (default: 10)
#
# What it does:
#   Each worker computes prime numbers up to a fixed ceiling.
#   Pure CPU work — no I/O, no sleep — so iowait stays near 0
#   and every second of runtime is genuine CPU pressure.
#
# Why primes?
#   Deterministic, portable (needs only bash+bc or python3),
#   scales cleanly with INTENSITY, and produces a measurable
#   result we can verify for correctness.
# ============================================================

set -euo pipefail

INTENSITY=${1:-1}      # parallel workers
DURATION=${2:-10}      # seconds of work per worker
PRIME_CEIL=50000       # count primes up to this number

# ── Validation ──────────────────────────────────────────────
if ! [[ "$INTENSITY" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: INTENSITY must be a positive integer (got: $INTENSITY)" >&2
    exit 1
fi
if ! [[ "$DURATION" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: DURATION must be a positive integer in seconds (got: $DURATION)" >&2
    exit 1
fi

# ── Worker function (runs in subshell) ──────────────────────
cpu_worker() {
    local worker_id=$1
    local end_time=$(( $(date +%s) + DURATION ))

    while (( $(date +%s) < end_time )); do
        # Sieve of Eratosthenes in Python3 — deterministic CPU burn
        python3 - <<PYEOF
import sys
n = $PRIME_CEIL
sieve = bytearray([1]) * (n + 1)
sieve[0] = sieve[1] = 0
for i in range(2, int(n**0.5) + 1):
    if sieve[i]:
        sieve[i*i::i] = bytearray(len(sieve[i*i::i]))
count = sum(sieve)
# Uncomment to verify: print(f"Worker $worker_id: {count} primes up to $PRIME_CEIL", file=sys.stderr)
PYEOF
    done
}

export -f cpu_worker
export DURATION PRIME_CEIL

# ── Launch ───────────────────────────────────────────────────
echo "[load] Starting $INTENSITY worker(s) for ${DURATION}s each (ceiling=$PRIME_CEIL)"
echo "[load] PID=$$  $(date '+%Y-%m-%d %H:%M:%S')"

PIDS=()
for (( i=1; i<=INTENSITY; i++ )); do
    cpu_worker "$i" &
    PIDS+=($!)
done

# Wait for all workers; propagate any failure
FAILED=0
for pid in "${PIDS[@]}"; do
    wait "$pid" || FAILED=1
done

if (( FAILED )); then
    echo "[load] ERROR: one or more workers failed" >&2
    exit 1
fi

echo "[load] Done. All $INTENSITY worker(s) finished."
