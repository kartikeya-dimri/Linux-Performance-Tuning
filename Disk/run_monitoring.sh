#!/bin/bash

WORKLOAD=$1
OUTPUT_DIR=$2

INTERVAL=1

mkdir -p "$OUTPUT_DIR"

echo "[+] Starting monitoring..."
echo "[+] Collecting system metadata..."

uname -a > "$OUTPUT_DIR/system_info.txt"
lsblk > "$OUTPUT_DIR/disk_layout.txt"
df -h > "$OUTPUT_DIR/filesystem_usage.txt"
free -m > "$OUTPUT_DIR/memory_snapshot.txt"

# Start monitoring (background)
iostat -x -m $INTERVAL > "$OUTPUT_DIR/iostat.log" &
PID_IOSTAT=$!

vmstat $INTERVAL > "$OUTPUT_DIR/vmstat.log" &
PID_VMSTAT=$!

mpstat -P ALL $INTERVAL > "$OUTPUT_DIR/mpstat.log" &
PID_MPSTAT=$!

pidstat -d -r $INTERVAL > "$OUTPUT_DIR/pidstat.log" &
PID_PIDSTAT=$!

(
while true; do
    date +"%F %T" >> "$OUTPUT_DIR/psi_io.log"
    cat /proc/pressure/io >> "$OUTPUT_DIR/psi_io.log"
    sleep $INTERVAL
done
) &
PID_PSI=$!

sleep 3

echo "[+] Running workload..."
./run_workload.sh $WORKLOAD

echo "[+] Stopping monitoring..."

kill $PID_IOSTAT 2>/dev/null
kill $PID_VMSTAT 2>/dev/null
kill $PID_MPSTAT 2>/dev/null
kill $PID_PIDSTAT 2>/dev/null
kill $PID_PSI 2>/dev/null

wait 2>/dev/null

echo "[+] Cleaning logs..."

grep -v "Linux" "$OUTPUT_DIR/iostat.log" | sed '/^$/d' > "$OUTPUT_DIR/iostat_clean.log"
grep -v "procs" "$OUTPUT_DIR/vmstat.log" | sed '/^$/d' > "$OUTPUT_DIR/vmstat_clean.log"

echo "[+] Done. Logs in $OUTPUT_DIR"