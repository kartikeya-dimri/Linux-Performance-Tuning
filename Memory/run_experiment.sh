#!/bin/bash

WORKLOAD=$1

if [ -z "$WORKLOAD" ]; then
    echo "Usage: $0 {alloc|cache|mix}"
    exit 1
fi

echo ""
echo "########################################"
echo "  Memory Tuning Experiment: $WORKLOAD"
echo "########################################"
echo ""

# ============================================================
# STEP 1 — Reset system state
# ============================================================
echo "[STEP 1/7] Resetting system state..."
./reset_system.sh

# ============================================================
# STEP 2 — Apply bad baseline config
# ============================================================
echo "[STEP 2/7] Applying BAD baseline memory config..."
echo "           swappiness=80  dirty_ratio=5  dirty_bg=2  thp=never"
sudo sysctl -w vm.swappiness=80            > /dev/null
sudo sysctl -w vm.dirty_ratio=5            > /dev/null
sudo sysctl -w vm.dirty_background_ratio=2 > /dev/null
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null
echo "[STEP 2/7] Bad baseline applied."
echo ""

# ============================================================
# STEP 3 — Run baseline workload + monitoring (90s)
# ============================================================
echo "[STEP 3/7] Running BASELINE workload ($WORKLOAD, 90s) with monitoring..."
echo "           Logs will be saved to run_before/"
./run_monitoring.sh $WORKLOAD run_before
echo "[STEP 3/7] Baseline workload done."
echo ""

# ============================================================
# STEP 4 — Extract features
# ============================================================
echo "[STEP 4/7] Extracting features from baseline logs..."
echo run_before | python3 mem_features_full.py

if [ ! -f "run_before/mem_features_full.json" ]; then
    echo "[ERROR] Feature extraction failed — aborting."
    exit 1
fi
echo "[STEP 4/7] Features saved to run_before/mem_features_full.json"
echo ""

# ============================================================
# STEP 5 — Tuning recommendation
# ============================================================
echo "[STEP 5/7] Generating tuning recommendation..."
echo ""
echo "run_before/mem_features_full.json" | python3 mem_tuning.py
echo ""
echo "------------------------------------------------------------"
echo "  Apply the commands printed above, then press ENTER."
echo "------------------------------------------------------------"
read

# ============================================================
# STEP 6 — Reset + run tuned workload
# ============================================================
echo "[STEP 6/7] Resetting system state before tuned run..."
./reset_system.sh

echo "[STEP 6/7] Running TUNED workload ($WORKLOAD, 90s) with monitoring..."
echo "           Logs will be saved to run_after/"
./run_monitoring.sh $WORKLOAD run_after
echo run_after | python3 mem_features_full.py
echo "[STEP 6/7] Tuned workload done."
echo ""

# ============================================================
# STEP 7 — Plots + stats
# ============================================================
echo "[STEP 7/7] Generating comparison plots..."
echo -e "run_before\nrun_after\n$WORKLOAD" | python3 mem_plots.py

echo "[STEP 7/7] Running statistical analysis (Mann-Whitney U)..."
python3 mem_stats.py intra run_before run_after

echo ""
echo "########################################"
echo "  DONE — check comparison_plots_${WORKLOAD}/"
echo "########################################"
