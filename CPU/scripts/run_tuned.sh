#!/usr/bin/env bash
# run_tuned.sh — Apply tunings and measure (State C1 and C2)
#
# Place at: CPU/scripts/run_tuned.sh
# Run from: CPU/ directory  →  bash scripts/run_tuned.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKLOAD="$PROJECT_DIR/workload/prime"
RESULTS="$PROJECT_DIR/results"

source "$SCRIPT_DIR/measure.sh"

# ── CONFIG ────────────────────────────────────────────────────────────────────
RUNS=15
THREADS=2
WAIT_BETWEEN=3
# ─────────────────────────────────────────────────────────────────────────────

# Pre-flight
if [[ ! -x "$WORKLOAD" ]]; then
    echo "[ERROR] Binary not found: $WORKLOAD"
    echo "        Run: bash workload/build.sh"
    exit 1
fi

if [[ ! -f "$RESULTS/state_B.csv" ]]; then
    echo "[ERROR] state_B.csv not found. Run run_baseline.sh first."
    exit 1
fi

# ── Detect same P-cores used in baseline ────────────────────────────────────
echo "[env] Detecting P-cores ..."
read -r CPU_P1 CPU_P2 < <(bash "$SCRIPT_DIR/detect_pcores.sh")
echo "[env] P-core 1 = cpu${CPU_P1}   P-core 2 = cpu${CPU_P2}"
echo ""

# ── Lock governor (must match baseline run) ───────────────────────────────────
if command -v cpupower &>/dev/null; then
    sudo cpupower frequency-set -g performance -q \
        && echo "[env] Governor: performance" \
        || echo "[WARN] Could not lock governor"
fi
echo ""

mkdir -p "$RESULTS"

echo "=== Tuned Runs ==="
echo "Date   : $(date)"
echo "Kernel : $(uname -r)"
echo ""

# ── STATE C1: Affinity split only ────────────────────────────────────────────
echo ">>> STATE C1: Affinity split — each process owns one dedicated P-core"
echo "    BG:  taskset -c ${CPU_P1} ./prime $THREADS"
echo "    FG:  taskset -c ${CPU_P2} ./prime $THREADS  (measured)"
echo ""

OUT_FILE="$RESULTS/state_C1.csv"
echo "run,wall_sec,cpu_migrations" > "$OUT_FILE"

for ((i=1; i<=RUNS; i++)); do
    echo -n "  Run $i/$RUNS ... "

    tmp_time=$(mktemp)
    tmp_perf=$(mktemp)

    taskset -c "$CPU_P1" "$WORKLOAD" "$THREADS" &>/dev/null &
    BG_PID=$!

    /usr/bin/time -f "%e" -o "$tmp_time" \
        perf stat -e cpu-migrations -o "$tmp_perf" -- \
        taskset -c "$CPU_P2" "$WORKLOAD" "$THREADS" \
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
echo ">>> C1 done. Results: $OUT_FILE"
echo ""

# ── STATE C2: Affinity split + RT scheduling ──────────────────────────────────
echo ">>> STATE C2: Affinity split + FIFO real-time scheduling (chrt -f 99)"
echo "    BG:  sudo chrt -f 99 taskset -c ${CPU_P1} ./prime $THREADS"
echo "    FG:  sudo chrt -f 99 taskset -c ${CPU_P2} ./prime $THREADS  (measured)"
echo ""

# Verify sudo + chrt work before starting the loop
if ! sudo chrt -f 10 true 2>/dev/null; then
    echo "[ERROR] sudo chrt failed. Cannot run C2."
    echo "        Try: sudo sysctl -w kernel.sched_rt_runtime_us=-1"
    exit 1
fi
echo "[env] chrt verified OK. RT throttle: $(cat /proc/sys/kernel/sched_rt_runtime_us)"
echo ""

OUT_FILE="$RESULTS/state_C2.csv"
echo "run,wall_sec,cpu_migrations" > "$OUT_FILE"

for ((i=1; i<=RUNS; i++)); do
    echo -n "  Run $i/$RUNS ... "

    tmp_time=$(mktemp)
    tmp_perf=$(mktemp)

    # Background: RT-elevated, pinned to P-core 1
    # Run as a direct sudo chrt invocation — no wrapper script
    sudo chrt -f 99 taskset -c "$CPU_P1" "$WORKLOAD" "$THREADS" &>/dev/null &
    BG_PID=$!

    # Foreground: measured from OUTSIDE the sudo boundary
    # /usr/bin/time and perf wrap the entire sudo+chrt+taskset+workload chain
    # cpu-migrations are still visible because perf attaches to the process tree
    /usr/bin/time -f "%e" -o "$tmp_time" \
        perf stat -e cpu-migrations -o "$tmp_perf" -- \
        sudo chrt -f 99 taskset -c "$CPU_P2" "$WORKLOAD" "$THREADS" \
        2>/dev/null

    wait "$BG_PID" 2>/dev/null || true

    wall=$(cat "$tmp_time")
    mig=$(grep -E 'cpu-migrations' "$tmp_perf" \
          | awk '{gsub(/,/,"",$1); print $1}')
    mig=${mig:-0}
    rm -f "$tmp_time" "$tmp_perf"

    # Guard: wall must be > 0.5s — sudo overhead alone is <0.01s
    if [[ -z "$wall" ]] || (( $(echo "$wall < 0.5" | bc -l) )); then
        echo "INVALID (wall=$wall) — skipping"
        continue
    fi

    echo "wall=${wall}s  migrations=${mig}"
    echo "${i},${wall},${mig}" >> "$OUT_FILE"
    sleep "$WAIT_BETWEEN"
done

VALID=$(tail -n +2 "$OUT_FILE" | wc -l)
echo ""
if [[ "$VALID" -eq 0 ]]; then
    echo "[ERROR] No valid C2 data. chrt may be silently failing."
    echo "        Paste this output: sudo chrt -f 99 taskset -c $CPU_P2 $WORKLOAD $THREADS"
else
    echo ">>> C2 done ($VALID/$RUNS valid runs). Results: $OUT_FILE"
fi

echo ""
echo ">>> ALL TUNED RUNS COMPLETE."
echo "    Now run: bash scripts/compare.sh"
