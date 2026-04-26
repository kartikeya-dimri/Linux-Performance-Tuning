#!/bin/bash

WORKLOAD=$1
ITERATIONS=$2
DEVICE="sda"

if [ -z "$WORKLOAD" ] || [ -z "$ITERATIONS" ]; then
    echo "Usage: $0 {rand|seq|mix} <iterations>"
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
    
    # BAD baseline (deliberately wrong config per workload)
    echo none | sudo tee /sys/block/$DEVICE/queue/scheduler > /dev/null
    if [ "$WORKLOAD" == "rand" ]; then
        sudo blockdev --setra 1024 /dev/$DEVICE
    elif [ "$WORKLOAD" == "seq" ]; then
        sudo blockdev --setra 32 /dev/$DEVICE
    elif [ "$WORKLOAD" == "mix" ]; then
        sudo blockdev --setra 4096 /dev/$DEVICE
    else
        sudo blockdev --setra 128 /dev/$DEVICE
    fi
    
    ./run_monitoring.sh $WORKLOAD run_before_$i
    echo run_before_$i | python3 disk_features_full.py
    
    # --- TUNING RUN ---
    # Only calculate tuning recommendations once, but apply it every time
    if [ "$i" -eq 1 ]; then
        echo ""
        echo "===== TUNING ====="
        echo -e "$DEVICE\nrun_before_1/disk_features_full.json" | python3 disk_tuning.py
        
        echo ""
        echo "Apply tuning manually and press ENTER to continue with the tuned runs"
        read
    else
        echo ""
        echo "===== TUNING ====="
        echo "Assuming tuning was already applied in Iteration 1."
    fi
    
    # --- TUNED RUN ---
    echo "===== TUNED RUN ====="
    ./reset_system.sh
    
    ./run_monitoring.sh $WORKLOAD run_after_$i
    echo run_after_$i | python3 disk_features_full.py
    
    # Intra-run stats for this specific iteration
    python3 disk_stats.py intra run_before_$i run_after_$i
done

# --- FINAL INTER-RUN STATS ---
echo ""
echo "================================================="
echo " ALL ITERATIONS COMPLETE"
echo "================================================="
python3 disk_stats.py inter $ITERATIONS

echo "DONE"
