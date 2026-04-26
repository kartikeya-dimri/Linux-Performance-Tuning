#!/bin/bash

WORKLOAD=$1
DEVICE="sda"

if [ -z "$WORKLOAD" ]; then
    echo "Usage: $0 {rand|seq|mix}"
    exit 1
fi

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

./run_monitoring.sh $WORKLOAD run_before

echo run_before | python3 disk_features_full.py

# Safety check
if [ ! -f "run_before/disk_features_full.json" ]; then
    echo "[ERROR] Feature extraction failed"
    exit 1
fi

echo "===== TUNING ====="

echo -e "$DEVICE\nrun_before/disk_features_full.json" | python3 disk_tuning.py

echo "Apply tuning manually and press ENTER"
read

echo "===== TUNED RUN ====="

./reset_system.sh

./run_monitoring.sh $WORKLOAD run_after

echo run_after | python3 disk_features_full.py

echo -e "run_before\nrun_after" | python3 disk_plots.py

# Statistical Significance (Intra-run)
python3 disk_stats.py intra run_before run_after

echo "DONE"