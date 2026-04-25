#!/bin/bash
# ============================================================
# run_baseline.sh — Full baseline capture (no tuning applied)
# ============================================================
# Usage: ./run_baseline.sh [RUNS] [INTENSITY] [DURATION]
#
# This script is the single entry point for Phase 1.
# It:
#   1. Locks the environment (records kernel, CPU, governor)
#   2. Calls measure.sh → writes to baseline/
#   3. Prints a clean summary to stdout
#
# Run this BEFORE any tuning. After tuning, run_after_tuning.sh
# calls the same measure.sh with identical parameters so results
# are directly comparable.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MEASURE_SCRIPT="$SCRIPT_DIR/../measure/measure.sh"
BASELINE_DIR="$PROJECT_ROOT/baseline"

RUNS=${1:-5}
INTENSITY=${2:-1}
DURATION=${3:-10}

mkdir -p "$BASELINE_DIR"

# ── 1. Environment snapshot ───────────────────────────────────
ENV_FILE="$BASELINE_DIR/environment.txt"
{
    echo "# Environment Snapshot — $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "[kernel]"
    uname -r
    echo ""
    echo "[cpu_model]"
    grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs
    echo ""
    echo "[cpu_count]"
    nproc
    echo ""
    echo "[cpu_governor]"
    # May not exist in all environments (e.g., VMs), so soft-fail
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unavailable"
    echo ""
    echo "[load_avg_before]"
    uptime | awk -F'load average:' '{print $2}'
    echo ""
    echo "[swappiness]"
    cat /proc/sys/vm/swappiness
    echo ""
    echo "[run_params]"
    echo "runs=$RUNS  intensity=$INTENSITY  duration=${DURATION}s"
} > "$ENV_FILE"

echo "----------------------------------------------"
echo " Environment snapshot → $ENV_FILE"
cat "$ENV_FILE"
echo "----------------------------------------------"
echo ""

# ── 2. Run measurements ───────────────────────────────────────
echo " Starting baseline measurement..."
echo ""
bash "$MEASURE_SCRIPT" "$BASELINE_DIR" "$RUNS" "$INTENSITY" "$DURATION"

# ── 3. Print summary ──────────────────────────────────────────
echo ""
echo "=============================================="
echo " BASELINE SUMMARY"
echo "=============================================="
cat "$BASELINE_DIR/summary.txt"
echo ""
echo " Raw data  : $BASELINE_DIR/raw.txt"
echo " Env info  : $ENV_FILE"
echo ""
echo " ✅ Baseline complete. Run tuning next:"
echo "    scripts/tune/tune.sh"
echo "=============================================="
