#!/bin/bash
# ============================================================
# tune.sh — CPU Tuning Experiments
# ============================================================
# Usage: ./tune.sh <EXPERIMENT> [RUNS] [DURATION]
#
#   EXPERIMENT options:
#     1  — taskset: pin workload to single core (avoid scheduler bounce)
#     2  — parallel: run 4 workers across 4 cores (parallelism speedup)
#     3  — both: taskset + parallel combined (4 workers, pinned to cores 0-3)
#
#   RUNS     : number of measurement runs (default: 5)
#   DURATION : seconds per worker         (default: 10)
#
# Results written to:
#   after_tuning/experiment_1/   taskset
#   after_tuning/experiment_2/   parallel
#   after_tuning/experiment_3/   both
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOAD_SCRIPT="$SCRIPT_DIR/../load/generate_load.sh"
MEASURE_SCRIPT="$SCRIPT_DIR/../measure/measure.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

EXPERIMENT=${1:?'Usage: tune.sh <EXPERIMENT: 1|2|3> [RUNS] [DURATION]'}
RUNS=${2:-5}
DURATION=${3:-10}

# ── Validate experiment number ───────────────────────────────
if ! [[ "$EXPERIMENT" =~ ^[123]$ ]]; then
    echo "ERROR: EXPERIMENT must be 1, 2, or 3" >&2
    exit 1
fi

# ── Check taskset is available (needed for exp 1 and 3) ─────
if [[ "$EXPERIMENT" == "1" || "$EXPERIMENT" == "3" ]]; then
    if ! command -v taskset &>/dev/null; then
        echo "ERROR: 'taskset' not found. Install with: sudo apt install util-linux" >&2
        exit 1
    fi
fi

# ── Experiment config ────────────────────────────────────────
case "$EXPERIMENT" in
    1)
        LABEL="taskset_single_core"
        DESCRIPTION="Pin 1 worker to core 0 — eliminates scheduler migration"
        INTENSITY=1
        USE_TASKSET=true
        CORES="0"
        ;;
    2)
        LABEL="parallel_4_workers"
        DESCRIPTION="4 workers across all cores — parallelism speedup"
        INTENSITY=4
        USE_TASKSET=false
        CORES=""
        ;;
    3)
        LABEL="taskset_plus_parallel"
        DESCRIPTION="4 workers pinned to cores 0-3 — combined tuning"
        INTENSITY=4
        USE_TASKSET=true
        CORES="0-3"
        ;;
esac

OUT_DIR="$PROJECT_ROOT/after_tuning/experiment_${EXPERIMENT}_${LABEL}"
mkdir -p "$OUT_DIR"

# ── Environment snapshot ─────────────────────────────────────
{
    echo "# Tuning Experiment $EXPERIMENT — $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "[experiment]"
    echo "label=$LABEL"
    echo "description=$DESCRIPTION"
    echo ""
    echo "[tuning_applied]"
    if [[ "$USE_TASKSET" == "true" ]]; then
        echo "taskset=yes (cores: $CORES)"
    else
        echo "taskset=no"
    fi
    echo "intensity=$INTENSITY"
    echo ""
    echo "[cpu_governor]"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unavailable"
    echo ""
    echo "[run_params]"
    echo "runs=$RUNS  intensity=$INTENSITY  duration=${DURATION}s"
} > "$OUT_DIR/environment.txt"

cat "$OUT_DIR/environment.txt"
echo ""

# ── Custom measurement loop with tuning applied ──────────────
RAW="$OUT_DIR/raw.txt"
SUMMARY="$OUT_DIR/summary.txt"

{
    echo "# Tuning Experiment $EXPERIMENT — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# label=$LABEL"
    echo "# intensity=$INTENSITY  duration=${DURATION}s  runs=$RUNS"
    echo "# run_id | elapsed_s | cpu_avg_%"
} > "$RAW"

read_cpu_ticks() {
    python3 -c "
with open('/proc/stat') as f:
    parts = f.readline().split()
total = sum(int(x) for x in parts[1:])
idle  = int(parts[4]) + int(parts[5])
print(total, idle)
"
}

echo "=============================================="
echo " Experiment $EXPERIMENT: $DESCRIPTION"
echo " Runs=$RUNS  Intensity=$INTENSITY  Duration=${DURATION}s"
echo "=============================================="

# Warm-up
echo -n "[tune] Warm-up (discarded) ... "
if [[ "$USE_TASKSET" == "true" ]]; then
    taskset -c "$CORES" bash "$LOAD_SCRIPT" "$INTENSITY" "$DURATION" > /dev/null 2>&1
else
    bash "$LOAD_SCRIPT" "$INTENSITY" "$DURATION" > /dev/null 2>&1
fi
echo "done"
sleep 2

for (( run=1; run<=RUNS; run++ )); do
    echo -n "[tune] Run $run/$RUNS ... "

    read TOTAL_BEFORE IDLE_BEFORE <<< "$(read_cpu_ticks)"

    if [[ "$USE_TASKSET" == "true" ]]; then
        ELAPSED=$(python3 - "$LOAD_SCRIPT" "$INTENSITY" "$DURATION" "$CORES" <<'PYEOF'
import subprocess, time, sys

load_script, intensity, duration, cores = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
start = time.perf_counter()
subprocess.run(
    ["taskset", "-c", cores, "bash", load_script, intensity, duration],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    check=True
)
end = time.perf_counter()
print(f"{end - start:.4f}")
PYEOF
)
    else
        ELAPSED=$(python3 - "$LOAD_SCRIPT" "$INTENSITY" "$DURATION" <<'PYEOF'
import subprocess, time, sys

load_script, intensity, duration = sys.argv[1], sys.argv[2], sys.argv[3]
start = time.perf_counter()
subprocess.run(
    ["bash", load_script, intensity, duration],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    check=True
)
end = time.perf_counter()
print(f"{end - start:.4f}")
PYEOF
)
    fi

    read TOTAL_AFTER IDLE_AFTER <<< "$(read_cpu_ticks)"

    CPU_AVG=$(python3 -c "
total_delta = $TOTAL_AFTER - $TOTAL_BEFORE
idle_delta  = $IDLE_AFTER  - $IDLE_BEFORE
util = 100.0 * (1 - idle_delta / total_delta) if total_delta > 0 else 0.0
print(f'{util:.1f}')
")

    echo "elapsed=${ELAPSED}s  cpu≈${CPU_AVG}%"
    echo "$run | $ELAPSED | $CPU_AVG" >> "$RAW"
    sleep 2
done

# ── Summary stats ────────────────────────────────────────────
python3 - "$RAW" "$SUMMARY" <<'PYEOF'
import sys, statistics

raw_file, summary_file = sys.argv[1], sys.argv[2]

elapsed_list, cpu_list = [], []
with open(raw_file) as f:
    for line in f:
        if line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) != 3:
            continue
        _, e, c = parts
        elapsed_list.append(float(e))
        cpu_list.append(float(c))

def stats(label, vals):
    if len(vals) > 1:
        return (f"{label}:\n"
                f"  min    = {min(vals):.4f}\n"
                f"  max    = {max(vals):.4f}\n"
                f"  mean   = {statistics.mean(vals):.4f}\n"
                f"  stdev  = {statistics.stdev(vals):.4f}\n")
    return f"{label}:\n  value  = {vals[0]:.4f}\n"

output = "\n".join([
    "# Summary Statistics",
    f"# runs={len(elapsed_list)}",
    "",
    stats("elapsed_time (s)", elapsed_list),
    stats("cpu_util    (%)", cpu_list),
])

print(output)
with open(summary_file, "w") as f:
    f.write(output + "\n")
PYEOF

echo ""
echo "=============================================="
echo " Results → $OUT_DIR"
echo " Next: run compare.sh to see % improvement"
echo "=============================================="
