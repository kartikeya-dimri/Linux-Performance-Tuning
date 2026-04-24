#!/bin/bash

# chmod +x run_monitoring.sh
# ==============================
# Monitoring Wrapper
# ==============================

OUTPUT_DIR="run_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "[+] Starting monitoring..."

# Start monitoring (background)
./disk_baseline_full.sh > "$OUTPUT_DIR/monitor.log" &
MONITOR_PID=$!

# Give monitoring time to stabilize
sleep 5

# Run workload (foreground)
./run_workload.sh $1

# Wait a bit after workload
sleep 5

# Stop monitoring
kill $MONITOR_PID 2>/dev/null

echo "[+] Monitoring + workload completed."
echo "[+] Data stored in: $OUTPUT_DIR"