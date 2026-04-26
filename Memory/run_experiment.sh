#!/bin/bash

WORKLOAD=$1
DEVICE="sda"

if [ -z "$WORKLOAD" ]; then
    echo "Usage: $0 {alloc|cache|mix}"
    exit 1
fi

echo "===== BASELINE RUN ====="

./reset_system.sh

# -----------------------------------------
# BAD baseline: deliberately wrong config per workload
# All workloads start with the same misconfiguration:
#   - swappiness=80  → swaps out anon pages too aggressively
#   - dirty_ratio=5  → flushes dirty pages too eagerly (bad for writes)
#   - thp=never      → disables huge pages (bad for alloc workloads)
# -----------------------------------------
echo "[+] Applying bad baseline memory config..."
sudo sysctl -w vm.swappiness=80
sudo sysctl -w vm.dirty_ratio=5
sudo sysctl -w vm.dirty_background_ratio=2
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null
echo "[+] Bad baseline applied: swappiness=80, dirty_ratio=5, thp=never"

./run_monitoring.sh $WORKLOAD run_before

echo run_before | python3 mem_features_full.py

# Safety check
if [ ! -f "run_before/mem_features_full.json" ]; then
    echo "[ERROR] Feature extraction failed — aborting."
    exit 1
fi

echo "===== TUNING ====="

echo -e "run_before/mem_features_full.json" | python3 mem_tuning.py

echo ""
echo "Apply the tuning commands printed above, then press ENTER to continue."
read

echo "===== TUNED RUN ====="

./reset_system.sh

./run_monitoring.sh $WORKLOAD run_after

echo run_after | python3 mem_features_full.py

echo -e "run_before\nrun_after\n$WORKLOAD" | python3 mem_plots.py

# Statistical Significance (Intra-run)
python3 mem_stats.py intra run_before run_after

echo "DONE"
