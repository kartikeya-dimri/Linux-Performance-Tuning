#!/bin/bash

# chmod +x run_workload.sh
# ==============================
# Workload Generator (fio)
# ==============================

WORKLOAD=$1   # seq | rand | mix
FILE="testfile"
SIZE="1G"
RUNTIME=60

echo "[+] Running workload: $WORKLOAD"

# Create test file if not exists
if [ ! -f "$FILE" ]; then
    echo "[+] Creating test file..."
    dd if=/dev/zero of=$FILE bs=1M count=1024 status=progress
fi

case $WORKLOAD in
    seq)
        fio --name=seq_read \
            --filename=$FILE \
            --size=$SIZE \
            --bs=1M \
            --rw=read \
            --iodepth=16 \
            --runtime=$RUNTIME \
            --time_based \
            --direct=1
        ;;
    rand)
        fio --name=rand_read \
            --filename=$FILE \
            --size=$SIZE \
            --bs=4k \
            --rw=randread \
            --iodepth=32 \
            --runtime=$RUNTIME \
            --time_based \
            --direct=1
        ;;
    mix)
        fio --name=rand_mix \
            --filename=$FILE \
            --size=$SIZE \
            --bs=4k \
            --rw=randrw \
            --rwmixread=70 \
            --iodepth=32 \
            --runtime=$RUNTIME \
            --time_based \
            --direct=1
        ;;
    *)
        echo "Usage: $0 {seq|rand|mix}"
        exit 1
        ;;
esac

echo "[+] Workload completed."