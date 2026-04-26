#!/bin/bash

WORKLOAD=$1
ITERATIONS=$2

if [ -z "$WORKLOAD" ] || [ -z "$ITERATIONS" ]; then
    echo "Usage: $0 {alloc|cache|mix} <iterations>"
    exit 1
fi

echo "================================================="
echo " REPEATED EXPERIMENT: $WORKLOAD ($ITERATIONS iterations)"
echo "================================================="

for i in $(seq 1 $ITERATIONS); do
    echo ""
    echo "-------------------------------------------------"
    echo " ITERATION $i / $ITERATIONS"
    echo "-------------------------------------------------"

    # --- BASELINE RUN ---
    echo "===== BASELINE RUN ====="
    ./reset_system.sh

    # Apply bad baseline config (same for all workloads)
    echo "[+] Applying bad baseline memory config..."
    sudo sysctl -w vm.swappiness=80
    sudo sysctl -w vm.dirty_ratio=5
    sudo sysctl -w vm.dirty_background_ratio=2
    echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null

    ./run_monitoring.sh $WORKLOAD run_before_$i
    echo run_before_$i | python3 mem_features_full.py

    # --- TUNING: auto-apply every iteration ---
    echo ""
    echo "===== TUNING (auto-applying) ====="
    python3 mem_tuning.py --apply run_before_${i}/mem_features_full.json

    # --- TUNED RUN ---
    echo "===== TUNED RUN ====="
    ./reset_system.sh

    ./run_monitoring.sh $WORKLOAD run_after_$i
    echo run_after_$i | python3 mem_features_full.py

    # Intra-run stats for this iteration
    python3 mem_stats.py intra run_before_$i run_after_$i
done

# --- FINAL INTER-RUN STATS ---
echo ""
echo "================================================="
echo " ALL ITERATIONS COMPLETE"
echo "================================================="
python3 mem_stats.py inter $ITERATIONS

echo "DONE"
