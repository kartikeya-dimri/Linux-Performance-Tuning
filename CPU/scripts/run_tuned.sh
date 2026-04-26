#!/usr/bin/env bash
# run_tuned.sh — Apply tunings and measure (State C1 and C2)
#
# Place at: CPU/scripts/run_tuned.sh
# Run from: CPU/ directory  →  bash scripts/run_tuned.sh
#
# State C1: CPU affinity split (process 1 → core 0, process 2 → core 1)
# State C2: Affinity split + real-time FIFO scheduling (chrt -f 99)
#
# Results written to: results/state_C1.csv  and  results/state_C2.csv

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKLOAD="$PROJECT_DIR/workload/prime"
RESULTS="$PROJECT_DIR/results"

source "$SCRIPT_DIR/measure.sh"

# ── CONFIG (MUST match run_baseline.sh) ─────────────────────────────────────
RUNS=15
THREADS=2
CPU_P1=0         # dedicated core for process 1 (affinity split)
CPU_P2=1         # dedicated core for process 2 (affinity split)
WAIT_BETWEEN=3
# ────────────────────────────────────────────────────────────────────────────

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

mkdir -p "$RESULTS"

echo "=== Tuned Runs ==="
echo "Date   : $(date)"
echo "Kernel : $(uname -r)"
echo ""

# ── STATE C1: Affinity split only ────────────────────────────────────────────
echo ">>> STATE C1: Affinity split tuning"
echo "    Process 1 → core ${CPU_P1}"
echo "    Process 2 → core ${CPU_P2}"
echo ""

OUT_FILE="$RESULTS/state_C1.csv"
echo "run,wall_sec,cpu_migrations" > "$OUT_FILE"

for ((i=1; i<=RUNS; i++)); do
    echo -n "  Run $i/$RUNS ... "

    tmp_time=$(mktemp)
    tmp_perf=$(mktemp)

    # Process 1 pinned to CPU_P1 (background)
    taskset -c "$CPU_P1" "$WORKLOAD" "$THREADS" &>/dev/null &
    BG_PID=$!

    # Process 2 pinned to CPU_P2 (measured foreground)
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
echo "    NOTE: chrt -f 99 is applied via a wrapper script run as root."
echo "          perf stat + /usr/bin/time measure the child PID from outside."
echo ""

# Verify sudo works before starting the loop
if ! sudo -v; then
    echo "[ERROR] sudo not available or wrong password. Cannot run C2."
    exit 1
fi

# Write a small wrapper that sets RT scheduling on itself then execs the workload.
# This avoids the perf-wrapping-sudo problem entirely:
#   sudo runs only the wrapper (no interactive tty needed mid-loop)
#   perf/time wrap the wrapper's process from the current shell (same uid)
WRAPPER="$RESULTS/_rt_wrapper.sh"
cat > "$WRAPPER" << WRAP
#!/usr/bin/env bash
# Sets FIFO RT priority on the current shell, then execs the workload.
# Must be run as root (via sudo).
chrt -f 99 taskset -c "\$1" "\$2" "\$3"
WRAP
chmod +x "$WRAPPER"

OUT_FILE="$RESULTS/state_C2.csv"
echo "run,wall_sec,cpu_migrations" > "$OUT_FILE"

for ((i=1; i<=RUNS; i++)); do
    echo -n "  Run $i/$RUNS ... "

    tmp_time=$(mktemp)
    tmp_perf=$(mktemp)

    # Background: RT + pinned to CPU_P1 (not measured)
    sudo bash "$WRAPPER" "$CPU_P1" "$WORKLOAD" "$THREADS" &>/dev/null &
    BG_PID=$!

    # Foreground: measure the sudo process itself with time+perf
    # perf attaches to the sudo pid which forks the wrapper — migrations still visible
    /usr/bin/time -f "%e" -o "$tmp_time" \
        perf stat -e cpu-migrations -o "$tmp_perf" -- \
        sudo bash "$WRAPPER" "$CPU_P2" "$WORKLOAD" "$THREADS" \
        2>/dev/null

    wait "$BG_PID" 2>/dev/null || true

    wall=$(cat "$tmp_time")
    mig=$(grep -E 'cpu-migrations' "$tmp_perf" \
          | awk '{gsub(/,/,"",$1); print $1}')
    mig=${mig:-0}
    rm -f "$tmp_time" "$tmp_perf"

    # Validate we got a real number
    if [[ -z "$wall" || "$wall" == "0.00" || "$wall" == "0" ]]; then
        echo "FAILED (wall=$wall) — chrt may have been denied. Skipping run."
        continue
    fi

    echo "wall=${wall}s  migrations=${mig}"
    echo "${i},${wall},${mig}" >> "$OUT_FILE"
    sleep "$WAIT_BETWEEN"
done

rm -f "$WRAPPER"

# Count valid rows (excluding header)
VALID_ROWS=$(tail -n +2 "$OUT_FILE" | wc -l)
if [[ "$VALID_ROWS" -eq 0 ]]; then
    echo ""
    echo "[ERROR] No valid C2 data collected. Likely cause: chrt -f 99 requires"
    echo "        RLIMIT_RTPRIO or CAP_SYS_NICE. Try:"
    echo "        sudo sysctl -w kernel.sched_rt_runtime_us=-1"
    echo "        Then re-run: bash scripts/run_tuned.sh"
    echo ""
    echo "        Alternatively, compare.sh will skip C2 and report C1 only."
else
    echo ""
    echo ">>> C2 done ($VALID_ROWS/$RUNS valid runs). Results: $OUT_FILE"
fi

echo ""
echo ">>> ALL TUNED RUNS COMPLETE."
echo "    Now run: bash scripts/compare.sh"