#!/bin/bash

WORKLOAD=$1
OUTDIR="run_before"

if [ -z "$WORKLOAD" ]; then
    echo "Usage: $0 {rand|seq|mix}"
    exit 1
fi

echo "=================================="
echo " BASELINE RUN"
echo "=================================="

./reset_system.sh
./set_baseline.sh

echo "[+] Running baseline experiment..."

./run_monitoring.sh $WORKLOAD $OUTDIR

echo "[+] Extracting features..."
echo $OUTDIR | python3 disk_features_full.py

echo "=================================="
echo " Baseline completed: $OUTDIR"
echo "=================================="