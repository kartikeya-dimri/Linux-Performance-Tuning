#!/usr/bin/env bash
# run_baseline.sh — Collect State A and State B measurements
#
# Place at: CPU/scripts/run_baseline.sh
# Run from: CPU/ directory  →  bash scripts/run_baseline.sh
#
# State A: clean system, no contention (true baseline)
# State B: synthetic contention on same CPUs (the "problem" we create)
#
# Results written to: results/state_A.csv  and  results/state_B.csv

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKLOAD="$PROJECT_DIR/workload/prime"
RESULTS="$PROJECT_DIR/results"

source "$SCRIPT_DIR/measure.sh"

# ── CONFIG ──────────────────────────────────────────────────────────────────
RUNS=15          # number of repeat runs per state
THREADS=2        # threads per prime instance
CPU_A=0          # core for process 1 in contention
CPU_B=1          # core for process 2 in contention
WAIT_BETWEEN=3   # seconds to wait between runs (let system settle)
# ────────────────────────────────────────────────────────────────────────────

# Pre-flight checks
if [[ ! -x "$WORKLOAD" ]]; then
    echo "[ERROR] Binary not found: $WORKLOAD"
    echo "        Run: bash workload/build.sh"
    exit 1
fi

if ! command -v perf &>/dev/null; then
    echo "[ERROR] perf not found. Install: sudo apt install linux-tools-common linux-tools-generic"
    exit 1
fi

if ! command -v cpupower &>/dev/null; then
    echo "[WARN] cpupower not found — CPU governor not locked."
    echo "       Install: sudo apt install linux-tools-common"
    echo "       Proceeding anyway, but results may have frequency variance."
else
    echo "[env] Locking CPU governor to performance ..."
    sudo cpupower frequency-set -g performance -q || echo "[WARN] Could not set governor (continue anyway)"
fi

mkdir -p "$RESULTS"

# Print environment snapshot
{
    echo "=== Environment Snapshot ==="
    echo "Date      : $(date)"
    echo "Kernel    : $(uname -r)"
    echo "CPU       : $(lscpu | grep 'Model name' | sed 's/.*: *//')"
    echo "Cores     : $(nproc)"
    echo "Governor  : $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'unknown')"
    echo "Runs      : $RUNS"
    echo "Threads   : $THREADS"
    echo "============================"
} | tee "$RESULTS/environment.txt"
echo ""

# ── STATE A: No contention, no tuning ───────────────────────────────────────
echo ">>> STATE A: Clean baseline (no contention, no tuning)"
echo "    Command: taskset -c ${CPU_A},${CPU_B} $WORKLOAD $THREADS"
echo ""

OUT_FILE="$RESULTS/state_A.csv"
echo "run,wall_sec,cpu_migrations" > "$OUT_FILE"

for ((i=1; i<=RUNS; i++)); do
    echo -n "  Run $i/$RUNS ... "
    result=$(measure_single taskset -c "${CPU_A},${CPU_B}" "$WORKLOAD" "$THREADS")
    wall=$(echo "$result" | grep -oP 'wall_sec=\K[0-9.]+')
    mig=$(echo "$result"  | grep -oP 'migrations=\K[0-9]+')
    echo "wall=${wall}s  migrations=${mig}"
    echo "${i},${wall},${mig}" >> "$OUT_FILE"
    sleep "$WAIT_BETWEEN"
done

echo ""
echo ">>> State A done. Results: $OUT_FILE"
echo ""

# ── STATE B: Synthetic contention (same CPUs, two competing processes) ───────
echo ">>> STATE B: Contention created (both processes on same CPUs)"
echo "    Command: taskset -c ${CPU_A},${CPU_B} ./prime & taskset -c ${CPU_A},${CPU_B} ./prime"
echo ""

OUT_FILE="$RESULTS/state_B.csv"
echo "run,wall_sec,cpu_migrations" > "$OUT_FILE"

for ((i=1; i<=RUNS; i++)); do
    echo -n "  Run $i/$RUNS (contention pair) ... "

    tmp_time=$(mktemp)
    tmp_perf=$(mktemp)

    # Launch background process (same CPUs — contention)
    taskset -c "${CPU_A},${CPU_B}" "$WORKLOAD" "$THREADS" &>/dev/null &
    BG_PID=$!

    # Measure foreground process (same CPUs — this is what we time)
    /usr/bin/time -f "%e" -o "$tmp_time" \
        perf stat -e cpu-migrations -o "$tmp_perf" -- \
        taskset -c "${CPU_A},${CPU_B}" "$WORKLOAD" "$THREADS" \
        2>/dev/null

    wait "$BG_PID" 2>/dev/null || true

    wall=$(cat "$tmp_time")
    mig=$(grep -E 'cpu-migrations' "$tmp_perf" \
          | awk '{gsub(/,/,"",$1); print $1}')
    mig=${mig:-0}
    rm -f "$tmp_time" "$tmp_perf"

    echo "wall=${wall}s  migrations=${mig}"
    echo "${i},${wall},${mig}" >> "$OUT_FILE"
    sleep "$WAIT_BETWEEN"
done

echo ""
echo ">>> State B done. Results: $OUT_FILE"
echo ""
echo ">>> BASELINE COLLECTION COMPLETE."
echo "    Now run: bash scripts/run_tuned.sh"
