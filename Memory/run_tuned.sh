#!/bin/bash

WORKLOAD=$1
RUNTIME=90

echo "[+] Running TUNED workload: $WORKLOAD"

if [ -z "$WORKLOAD" ]; then
    echo "Usage: $0 {alloc|cache|mix}"
    exit 1
fi

./reset_system.sh
./run_monitoring.sh $WORKLOAD run_after

echo "[+] Extracting features from tuned run..."
echo run_after | python3 mem_features_full.py

echo "=================================="
echo " Tuned run completed: run_after"
echo "=================================="
