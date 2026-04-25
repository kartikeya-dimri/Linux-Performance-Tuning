#!/bin/bash
# generate_load.sh — Work-controlled CPU workload
# Usage: ./generate_load.sh [ITERATIONS] [WORKERS]
#   ITERATIONS : total sieve computations to complete (default: 200)
#   WORKERS    : parallel processes                   (default: 1)

set -euo pipefail

ITERATIONS=${1:-200}
WORKERS=${2:-1}

PER_WORKER=$(( ITERATIONS / WORKERS ))
PRIME_CEIL=50000

echo "[load] Starting $WORKERS worker(s) x $PER_WORKER iterations each (total=$ITERATIONS)"

cpu_worker() {
    local count=$1
    python3 -c "
for _ in range($count):
    n = $PRIME_CEIL
    sieve = bytearray([1]) * (n + 1)
    sieve[0] = sieve[1] = 0
    for i in range(2, int(n**0.5) + 1):
        if sieve[i]:
            sieve[i*i::i] = bytearray(len(sieve[i*i::i]))
"
}

export -f cpu_worker
export PRIME_CEIL

PIDS=()
for (( i=1; i<=WORKERS; i++ )); do
    cpu_worker "$PER_WORKER" &
    PIDS+=($!)
done

for pid in "${PIDS[@]}"; do wait "$pid"; done
echo "[load] Done."