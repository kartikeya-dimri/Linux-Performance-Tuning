#!/bin/bash

WORKLOAD=$1
OUTPUT_DIR=$2

INTERVAL=1

mkdir -p "$OUTPUT_DIR"

echo "[+] Starting memory monitoring into: $OUTPUT_DIR"
echo "[+] Collecting system metadata..."

uname -a > "$OUTPUT_DIR/system_info.txt"
free -m  > "$OUTPUT_DIR/memory_snapshot.txt"

# -----------------------------------------
# Background: vmstat (classic swap/memory cols)
# Columns we care about: si, so, free, buff, cache, wa
# -----------------------------------------
vmstat $INTERVAL > "$OUTPUT_DIR/vmstat.log" &
PID_VMSTAT=$!

# -----------------------------------------
# Background: periodic /proc/meminfo snapshots
# Captures: MemFree, MemAvailable, Cached, Buffers, SwapUsed, etc.
# -----------------------------------------
(
while true; do
    echo "---SNAPSHOT---" >> "$OUTPUT_DIR/meminfo.log"
    date +"%F %T"       >> "$OUTPUT_DIR/meminfo.log"
    cat /proc/meminfo   >> "$OUTPUT_DIR/meminfo.log"
    sleep $INTERVAL
done
) &
PID_MEMINFO=$!

# -----------------------------------------
# Background: periodic /proc/vmstat snapshots
# Captures: pgfault, pgmajfault, pswpin, pswpout deltas
# -----------------------------------------
(
while true; do
    echo "---SNAPSHOT---" >> "$OUTPUT_DIR/vmstat_proc.log"
    date +"%F %T"        >> "$OUTPUT_DIR/vmstat_proc.log"
    cat /proc/vmstat     >> "$OUTPUT_DIR/vmstat_proc.log"
    sleep $INTERVAL
done
) &
PID_VMSTAT_PROC=$!

# -----------------------------------------
# Background: /proc/pressure/memory (PSI)
# -----------------------------------------
(
while true; do
    date +"%F %T"              >> "$OUTPUT_DIR/psi_mem.log"
    cat /proc/pressure/memory  >> "$OUTPUT_DIR/psi_mem.log"
    sleep $INTERVAL
done
) &
PID_PSI=$!

# Let monitors warm up
sleep 3

echo "[+] Running workload..."
./run_workload.sh $WORKLOAD

echo "[+] Stopping monitoring..."

kill $PID_VMSTAT      2>/dev/null
kill $PID_MEMINFO     2>/dev/null
kill $PID_VMSTAT_PROC 2>/dev/null
kill $PID_PSI         2>/dev/null

wait 2>/dev/null

echo "[+] Cleaning logs..."

# Remove vmstat header noise (lines starting with 'procs')
grep -v "procs" "$OUTPUT_DIR/vmstat.log" | sed '/^$/d' > "$OUTPUT_DIR/vmstat_clean.log"

echo "[+] Done. Logs saved in $OUTPUT_DIR"
