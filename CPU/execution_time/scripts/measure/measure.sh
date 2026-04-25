#!/bin/bash
# ============================================================
# measure.sh — Execution time + CPU utilization measurement
# ============================================================
# Usage: ./measure.sh <OUTPUT_DIR> [RUNS] [INTENSITY] [DURATION]
#   OUTPUT_DIR : where to write raw.txt and summary.txt
#   RUNS       : number of measurement runs         (default: 5)
#   INTENSITY  : passed through to generate_load.sh (default: 1)
#   DURATION   : passed through to generate_load.sh (default: 10)
#
# Outputs (in OUTPUT_DIR/):
#   raw.txt     — one line per run: run_id, elapsed_s, cpu_avg_%
#   summary.txt — min / max / mean / stdev across all runs
#
# Dependencies: python3 (stdlib only), bash
# Uses /proc/stat for CPU — no vmstat, no /usr/bin/time needed.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOAD_SCRIPT="$SCRIPT_DIR/../load/generate_load.sh"

OUTPUT_DIR=${1:?'Usage: measure.sh <OUTPUT_DIR> [RUNS] [INTENSITY] [DURATION]'}
RUNS=${2:-5}
INTENSITY=${3:-1}
DURATION=${4:-10}

mkdir -p "$OUTPUT_DIR"
RAW="$OUTPUT_DIR/raw.txt"
SUMMARY="$OUTPUT_DIR/summary.txt"

# ── Header ───────────────────────────────────────────────────
{
    echo "# CPU Measurement — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# intensity=$INTENSITY  duration=${DURATION}s  runs=$RUNS"
    echo "# run_id | elapsed_s | cpu_avg_%"
} > "$RAW"

echo "=============================================="
echo " Measuring: $RUNS run(s)  intensity=$INTENSITY  duration=${DURATION}s"
echo "=============================================="

# ── Helper: read total and idle CPU ticks from /proc/stat ────
read_cpu_ticks() {
    python3 -c "
with open('/proc/stat') as f:
    parts = f.readline().split()   # cpu  user nice system idle iowait irq softirq ...
total = sum(int(x) for x in parts[1:])
idle  = int(parts[4]) + int(parts[5])  # idle + iowait
print(total, idle)
"
}

# ── Warm-up (not recorded) ───────────────────────────────────
echo -n "[measure] Warm-up (discarded) ... "
bash "$LOAD_SCRIPT" "$INTENSITY" "$DURATION" > /dev/null 2>&1
echo "done"
sleep 2

# ── Measurement loop ─────────────────────────────────────────
for (( run=1; run<=RUNS; run++ )); do
    echo -n "[measure] Run $run/$RUNS ... "

    # CPU snapshot before
    read TOTAL_BEFORE IDLE_BEFORE <<< "$(read_cpu_ticks)"

    # Time the workload with Python's high-res clock
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

    # CPU snapshot after
    read TOTAL_AFTER IDLE_AFTER <<< "$(read_cpu_ticks)"

    # CPU utilisation = 1 - (delta_idle / delta_total)
    CPU_AVG=$(python3 -c "
total_delta = $TOTAL_AFTER - $TOTAL_BEFORE
idle_delta  = $IDLE_AFTER  - $IDLE_BEFORE
if total_delta > 0:
    util = 100.0 * (1 - idle_delta / total_delta)
    print(f'{util:.1f}')
else:
    print('0.0')
")

    echo "elapsed=${ELAPSED}s  cpu≈${CPU_AVG}%"
    echo "$run | $ELAPSED | $CPU_AVG" >> "$RAW"

    sleep 2  # cooldown between runs
done

# ── Summary statistics ────────────────────────────────────────
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
echo " Results written to:"
echo "   $RAW"
echo "   $SUMMARY"
echo "=============================================="
