#!/usr/bin/env bash
# run_baseline.sh — Collect State A and State B measurements
#
# Place at: CPU/scripts/run_baseline.sh
# Run from: CPU/ directory  →  bash scripts/run_baseline.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKLOAD="$PROJECT_DIR/workload/prime"
RESULTS="$PROJECT_DIR/results"

source "$SCRIPT_DIR/measure.sh"

# ── CONFIG ───────────────────────────────────────────────────────────────────
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

if ! command -v perf &>/dev/null; then
    echo "[ERROR] perf not found."
    echo "        Install: sudo apt install linux-tools-common linux-tools-generic linux-tools-\$(uname -r)"
    exit 1
fi

# ── Detect P-cores ───────────────────────────────────────────────────────────
echo "[env] Detecting P-cores (highest max_freq cores) ..."
read -r CPU_A CPU_B < <(bash "$SCRIPT_DIR/detect_pcores.sh")
echo "[env] Selected cores: CPU_A=$CPU_A  CPU_B=$CPU_B"

# Verify they are actually P-cores by printing their max freq
for c in $CPU_A $CPU_B; do
    freq=$(cat /sys/devices/system/cpu/cpu${c}/cpufreq/cpuinfo_max_freq 2>/dev/null || echo "unknown")
    echo "[env] cpu${c} max_freq = ${freq} kHz"
done
echo ""

# ── Lock CPU governor ─────────────────────────────────────────────────────────
if command -v cpupower &>/dev/null; then
    echo "[env] Locking CPU governor to performance ..."
    sudo cpupower frequency-set -g performance -q \
        && echo "[env] Governor locked: performance" \
        || echo "[WARN] Could not set governor — results may have frequency variance"
else
    echo "[WARN] cpupower not found. Governor NOT locked."
    echo "       Install: sudo apt install linux-tools-common"
    echo "       Proceeding, but stdev may be higher."
fi

CUR_GOV=$(cat /sys/devices/system/cpu/cpu${CPU_A}/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
echo "[env] Governor on cpu${CPU_A}: $CUR_GOV"
echo ""

mkdir -p "$RESULTS"

# ── Environment snapshot ──────────────────────────────────────────────────────
{
    echo "=== Environment Snapshot ==="
    echo "Date      : $(date)"
    echo "Kernel    : $(uname -r)"
    echo "CPU       : $(lscpu | grep 'Model name' | sed 's/.*: *//')"
    echo "Cores     : $(nproc)"
    echo "Governor  : $CUR_GOV"
    echo "P-core A  : cpu${CPU_A} ($(cat /sys/devices/system/cpu/cpu${CPU_A}/cpufreq/cpuinfo_max_freq 2>/dev/null || echo '?') kHz)"
    echo "P-core B  : cpu${CPU_B} ($(cat /sys/devices/system/cpu/cpu${CPU_B}/cpufreq/cpuinfo_max_freq 2>/dev/null || echo '?') kHz)"
    echo "Runs      : $RUNS"
    echo "Threads   : $THREADS"
    echo "RT throttle: $(cat /proc/sys/kernel/sched_rt_runtime_us)"
    echo "============================"
} | tee "$RESULTS/environment.txt"
echo ""

# ── STATE A: Clean baseline ───────────────────────────────────────────────────
echo ">>> STATE A: Clean baseline (single process, both P-cores, no contention)"
echo "    Command: taskset -c ${CPU_A},${CPU_B} ./prime $THREADS"
echo ""

OUT_FILE="$RESULTS/state_A.csv"
echo "run,wall_sec,cpu_migrations" > "$OUT_FILE"

for ((i=1; i<=RUNS; i++)); do
    echo -n "  Run $i/$RUNS ... "

    tmp_time=$(mktemp)
    tmp_perf=$(mktemp)

    /usr/bin/time -f "%e" -o "$tmp_time" \
        perf stat -e cpu-migrations -o "$tmp_perf" -- \
        taskset -c "${CPU_A},${CPU_B}" "$WORKLOAD" "$THREADS" \
        2>/dev/null

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
echo ">>> State A done. Results: $OUT_FILE"
echo ""

# ── STATE B: Synthetic contention ────────────────────────────────────────────
echo ">>> STATE B: Contention (two processes competing on same two P-cores)"
echo "    BG:  taskset -c ${CPU_A},${CPU_B} ./prime $THREADS"
echo "    FG:  taskset -c ${CPU_A},${CPU_B} ./prime $THREADS  (measured)"
echo ""

OUT_FILE="$RESULTS/state_B.csv"
echo "run,wall_sec,cpu_migrations" > "$OUT_FILE"

for ((i=1; i<=RUNS; i++)); do
    echo -n "  Run $i/$RUNS (contention pair) ... "

    tmp_time=$(mktemp)
    tmp_perf=$(mktemp)

    # Background process — same CPU set, creates contention
    taskset -c "${CPU_A},${CPU_B}" "$WORKLOAD" "$THREADS" &>/dev/null &
    BG_PID=$!

    # Foreground — measured
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
