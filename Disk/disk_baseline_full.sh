#!/bin/bash

# execute as : 
# chmod +x disk_baseline_full.sh
# ./disk_baseline_full.sh

# ==========================================
# Comprehensive Disk Baseline Collection
# ==========================================

DURATION=60        # seconds
INTERVAL=1         # sampling interval
OUTPUT_DIR="disk_baseline_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$OUTPUT_DIR"

echo "Starting comprehensive disk baseline collection..."
echo "Duration: $DURATION seconds"
echo "Interval: $INTERVAL sec"
echo "Output: $OUTPUT_DIR"

# ------------------------------------------
# System Snapshot (one-time)
# ------------------------------------------
echo "[+] Collecting system metadata..."

uname -a > "$OUTPUT_DIR/system_info.txt"
lsblk -o NAME,KNAME,TYPE,SIZE,ROTA,MOUNTPOINT > "$OUTPUT_DIR/disk_layout.txt"
df -h > "$OUTPUT_DIR/filesystem_usage.txt"
free -m > "$OUTPUT_DIR/memory_snapshot.txt"
uptime > "$OUTPUT_DIR/uptime_snapshot.txt"
cat /proc/cpuinfo > "$OUTPUT_DIR/cpuinfo.txt"

# ------------------------------------------
# Start Monitoring Processes
# ------------------------------------------

echo "[+] Starting monitoring tools..."

# iostat (FULL extended metrics)
iostat -x -m $INTERVAL > "$OUTPUT_DIR/iostat.log" &
PID_IOSTAT=$!

# vmstat (CPU + iowait + memory)
vmstat $INTERVAL > "$OUTPUT_DIR/vmstat.log" &
PID_VMSTAT=$!

# mpstat (per CPU)
mpstat -P ALL $INTERVAL > "$OUTPUT_DIR/mpstat.log" &
PID_MPSTAT=$!

# pidstat (per-process disk + memory)
pidstat -d -r $INTERVAL > "$OUTPUT_DIR/pidstat.log" &
PID_PIDSTAT=$!

# uptime (continuous load avg logging)
(
while true; do
    date +"%F %T" >> "$OUTPUT_DIR/uptime.log"
    uptime >> "$OUTPUT_DIR/uptime.log"
    sleep $INTERVAL
done
) &
PID_UPTIME=$!

# PSI (I/O pressure stall info)
(
while true; do
    date +"%F %T" >> "$OUTPUT_DIR/psi_io.log"
    cat /proc/pressure/io >> "$OUTPUT_DIR/psi_io.log"
    sleep $INTERVAL
done
) &
PID_PSI=$!

# /proc/diskstats (raw kernel counters)
(
while true; do
    date +"%F %T" >> "$OUTPUT_DIR/diskstats.log"
    cat /proc/diskstats >> "$OUTPUT_DIR/diskstats.log"
    sleep $INTERVAL
done
) &
PID_DISKSTATS=$!

# ------------------------------------------
# Run for fixed duration
# ------------------------------------------
echo "[+] Collecting data..."
sleep $DURATION

# ------------------------------------------
# Stop all background processes
# ------------------------------------------
echo "[+] Stopping monitoring..."

kill $PID_IOSTAT 2>/dev/null
kill $PID_VMSTAT 2>/dev/null
kill $PID_MPSTAT 2>/dev/null
kill $PID_PIDSTAT 2>/dev/null
kill $PID_UPTIME 2>/dev/null
kill $PID_PSI 2>/dev/null
kill $PID_DISKSTATS 2>/dev/null

wait 2>/dev/null

echo "[+] Collection complete."

# ------------------------------------------
# Basic Cleaning / Structuring
# ------------------------------------------

echo "[+] Preparing cleaned outputs..."

# Clean iostat header noise
grep -v "Linux" "$OUTPUT_DIR/iostat.log" | sed '/^$/d' > "$OUTPUT_DIR/iostat_clean.log"

# Clean vmstat header
grep -v "procs" "$OUTPUT_DIR/vmstat.log" | sed '/^$/d' > "$OUTPUT_DIR/vmstat_clean.log"

# Extract only relevant iostat columns (optional quick view)
awk '
/Device/ {header=$0}
!/Device/ && NF>0 {print header "\n" $0}
' "$OUTPUT_DIR/iostat_clean.log" > "$OUTPUT_DIR/iostat_structured.log"

echo "[+] Summary of collected signals:"
echo "  - Disk utilization, latency, IOPS, throughput (iostat)"
echo "  - Read vs write latency + request size"
echo "  - CPU iowait + system activity (vmstat)"
echo "  - Per-process disk usage (pidstat)"
echo "  - Load average over time (uptime)"
echo "  - I/O stall pressure (PSI)"
echo "  - Raw disk counters (/proc/diskstats)"

echo "[+] All logs available in: $OUTPUT_DIR"