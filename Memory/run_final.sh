#!/bin/bash

# ============================================================
# run_final.sh — Multi-iteration alloc + cache experiment
#
# Usage: ./run_final.sh [N_ITERATIONS]
#   N_ITERATIONS: number of times to repeat each workload (default 5)
#
# Each iteration saves full logs to:
#   logs/alloc/iter_<N>/before/   — baseline logs
#   logs/alloc/iter_<N>/after/    — tuned logs
#   logs/cache/iter_<N>/before/
#   logs/cache/iter_<N>/after/
#
# After all runs, features are averaged and final plots generated.
# ============================================================

N=${1:-5}
WORKLOADS=("alloc" "cache")

echo ""
echo "========================================================"
echo "  Memory Tuning — Final Multi-Iteration Experiment"
echo "  Workloads : alloc + cache"
echo "  Iterations: $N per workload"
echo "  Estimated time: ~$((N * 2 * 7)) minutes"
echo "========================================================"
echo ""

mkdir -p logs

# Helper: run one full experiment iteration
# Args: $1=workload, $2=iteration number
run_one_iter() {
    local WORKLOAD=$1
    local ITER=$2
    local BEFORE_DIR="logs/${WORKLOAD}/iter_${ITER}/before"
    local AFTER_DIR="logs/${WORKLOAD}/iter_${ITER}/after"

    mkdir -p "$BEFORE_DIR" "$AFTER_DIR"

    echo ""
    echo "------------------------------------------------------------"
    echo "  [$WORKLOAD] Iteration $ITER / $N"
    echo "------------------------------------------------------------"

    # ---- STEP A: Reset + apply bad config ----
    echo "[A] Resetting system..."
    ./reset_system.sh

    echo "[A] Applying BAD baseline config..."
    sudo sysctl -w vm.swappiness=200            > /dev/null
    sudo sysctl -w vm.vfs_cache_pressure=500    > /dev/null
    sudo sysctl -w vm.dirty_ratio=5             > /dev/null
    sudo sysctl -w vm.dirty_background_ratio=2  > /dev/null
    sudo sysctl -w vm.min_free_kbytes=16384     > /dev/null
    echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null
    echo "[A] Bad config active."

    # ---- STEP B: Run baseline workload (monitoring + stress-ng) ----
    echo "[B] Running BASELINE workload (90s)..."
    ./run_monitoring.sh "$WORKLOAD" "$BEFORE_DIR"
    echo "$BEFORE_DIR" | python3 mem_features_full.py
    echo "[B] Baseline done. Features: $BEFORE_DIR/mem_features_full.json"

    # ---- STEP C: Auto-tune and apply ----
    echo "[C] Computing + applying tuning..."
    python3 mem_tuning.py --apply "$BEFORE_DIR/mem_features_full.json"

    # ---- STEP D: Reset + run tuned workload ----
    echo "[D] Resetting system before tuned run..."
    ./reset_system.sh

    echo "[D] Running TUNED workload (90s)..."
    ./run_monitoring.sh "$WORKLOAD" "$AFTER_DIR"
    echo "$AFTER_DIR" | python3 mem_features_full.py
    echo "[D] Tuned done. Features: $AFTER_DIR/mem_features_full.json"

    echo "[✓] Iteration $ITER complete for $WORKLOAD"
}

# ============================================================
# Run all iterations for all workloads
# ============================================================
for WORKLOAD in "${WORKLOADS[@]}"; do
    echo ""
    echo "========================================================"
    echo "  Starting workload: $WORKLOAD ($N iterations)"
    echo "========================================================"
    for i in $(seq 1 $N); do
        run_one_iter "$WORKLOAD" "$i"
    done
done

# ============================================================
# Compute averages across iterations
# ============================================================
echo ""
echo "========================================================"
echo "  Computing averaged features across $N iterations..."
echo "========================================================"
python3 mem_avg.py "$N" "${WORKLOADS[@]}"

# ============================================================
# Generate final plots from averaged data
# ============================================================
echo ""
echo "========================================================"
echo "  Generating final comparison plots..."
echo "========================================================"
for WORKLOAD in "${WORKLOADS[@]}"; do
    echo -e "logs/${WORKLOAD}/avg_before.json\nlogs/${WORKLOAD}/avg_after.json\n${WORKLOAD}_final" | python3 mem_plots_avg.py
done

echo ""
echo "========================================================"
echo "  ALL DONE"
echo "  Logs        : logs/alloc/  logs/cache/"
echo "  Avg features: logs/alloc/avg_before.json  logs/alloc/avg_after.json"
echo "  Avg features: logs/cache/avg_before.json  logs/cache/avg_after.json"
echo "  Final plots : comparison_plots_alloc_final/"
echo "                comparison_plots_cache_final/"
echo "========================================================"
