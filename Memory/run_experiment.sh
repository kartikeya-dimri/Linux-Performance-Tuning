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
# STEP 2 — Apply BAD baseline config (maximally wrong)
# ============================================================
echo "[STEP 2/7] Applying MAXIMALLY BAD baseline memory config..."
echo "           swappiness=200  vfs_cache_pressure=500  min_free_kbytes=16384  thp=never"
echo ""

# swappiness=200: kernel treats anonymous pages as almost disposable
# (max possible on Linux ≥ 5.8 — 20× more aggressive than tuned value of 10)
sudo sysctl -w vm.swappiness=200            > /dev/null

# vfs_cache_pressure=500: kernel evicts page cache 5× more aggressively than normal
sudo sysctl -w vm.vfs_cache_pressure=500    > /dev/null

# dirty_ratio=5: flush dirty pages to disk very eagerly (bad for write throughput)
sudo sysctl -w vm.dirty_ratio=5             > /dev/null
sudo sysctl -w vm.dirty_background_ratio=2  > /dev/null

# min_free_kbytes=16384: very small reserve — kernel waits until nearly OOM to reclaim
# (late reclaim = sudden stalls rather than smooth background work)
sudo sysctl -w vm.min_free_kbytes=16384     > /dev/null

# THP=never: force 4 KB pages — maximum TLB pressure for bulk allocations
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null

echo "[STEP 2/7] Bad baseline applied:"
sysctl vm.swappiness vm.vfs_cache_pressure vm.dirty_ratio vm.min_free_kbytes 2>/dev/null
echo ""

# ============================================================
# STEP 3 — Run baseline workload + monitoring (90s)
# ============================================================
echo "[STEP 3/7] Running BASELINE workload ($WORKLOAD, 90s) inside 4GB cgroup..."
echo "           Logs → run_before/"
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
# STEP 5 — Auto-tune and apply
# ============================================================
echo "[STEP 5/7] Computing tuning recommendation and applying automatically..."
echo ""
python3 mem_tuning.py --apply run_before/mem_features_full.json
echo ""
echo "[STEP 5/7] Tuning applied."
echo ""

# ============================================================
# STEP 6 — Reset + run tuned workload
# ============================================================
echo "[STEP 6/7] Resetting system state before tuned run..."
./reset_system.sh

echo "[STEP 6/7] Running TUNED workload ($WORKLOAD, 90s) inside 4GB cgroup..."
echo "           Logs → run_after/"
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
