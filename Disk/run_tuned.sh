#!/bin/bash

WORKLOAD=$1
FILE="testfile"
SIZE="4G"
RUNTIME=90

echo "[+] Running workload: $WORKLOAD"

if [ ! -f "$FILE" ]; then
    echo "[+] Creating large test file..."
    dd if=/dev/zero of=$FILE bs=1M count=4096 status=progress
fi

case $WORKLOAD in
    seq)
        fio --name=seq_read \
            --filename=$FILE \
            --size=$SIZE \
            --bs=1M \
            --rw=read \
            --iodepth=64 \
            --numjobs=2 \
            --ioengine=libaio \
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
            --iodepth=64 \
            --numjobs=4 \
            --ioengine=libaio \
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
            --iodepth=64 \
            --numjobs=4 \
            --ioengine=libaio \
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