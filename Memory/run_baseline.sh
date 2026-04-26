#!/bin/bash

WORKLOAD=$1
OUTDIR="run_before"

if [ -z "$WORKLOAD" ]; then
    echo "Usage: $0 {alloc|cache|mix}"
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
echo $OUTDIR | python3 mem_features_full.py

echo "=================================="
echo " Baseline completed: $OUTDIR"
echo "=================================="
