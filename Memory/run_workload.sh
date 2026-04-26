#!/bin/bash

WORKLOAD=$1
OUTPUT_DIR=${2:-.}   # second arg = output dir for stress-ng log

RUNTIME=90

echo "[+] Running memory workload: $WORKLOAD (output: $OUTPUT_DIR)"

mkdir -p "$OUTPUT_DIR"
STRESS_LOG="$OUTPUT_DIR/stress_ng.log"

case $WORKLOAD in

    # -----------------------------------------
    # ALLOC — Anonymous memory pressure inside a 4 GB cgroup cap
    # 4 workers × 90% of 4 GB = ~3.6 GB fighting for 4 GB physical
    # --vm-method refill: continuously writes fresh data → every page touched
    # Bad config: swappiness=200 → kernel swaps pages out immediately
    # Good config: swappiness=10 → kernel fights to keep pages in RAM
    # -----------------------------------------
    alloc)
        echo "[+] Creating 4 GB memory cgroup limit via systemd-run..."
        sudo systemd-run --scope \
            -p MemoryMax=4G \
            -p MemorySwapMax=8G \
            -- \
            stress-ng --vm 4 \
                      --vm-bytes 90% \
                      --vm-method refill \
                      --metrics-brief \
                      --timeout ${RUNTIME}s \
            2>&1 | tee "$STRESS_LOG"
        ;;

    # -----------------------------------------
    # CACHE — Page cache + CPU cache thrash inside 3 GB cgroup cap
    # Forces cache eviction because the cgroup limit is smaller than
    # the working set the cache stressor is trying to access.
    # -----------------------------------------
    cache)
        echo "[+] Creating 3 GB memory cgroup limit via systemd-run..."
        sudo systemd-run --scope \
            -p MemoryMax=3G \
            -p MemorySwapMax=8G \
            -- \
            stress-ng --cache 4 \
                      --cache-size 512M \
                      --metrics-brief \
                      --timeout ${RUNTIME}s \
            2>&1 | tee "$STRESS_LOG"
        ;;

    # -----------------------------------------
    # MIX — Combined anon + cache pressure inside 4 GB cap
    # 2 VM workers + 2 cache workers = genuine mixed eviction pressure
    # -----------------------------------------
    mix)
        echo "[+] Creating 4 GB memory cgroup limit via systemd-run..."
        sudo systemd-run --scope \
            -p MemoryMax=4G \
            -p MemorySwapMax=8G \
            -- \
            stress-ng --vm 2 \
                      --vm-bytes 80% \
                      --vm-method refill \
                      --cache 2 \
                      --cache-size 512M \
                      --metrics-brief \
                      --timeout ${RUNTIME}s \
            2>&1 | tee "$STRESS_LOG"
        ;;

    *)
        echo "Usage: $0 {alloc|cache|mix} [output_dir]"
        exit 1
        ;;
esac

echo "[+] Workload completed. Metrics saved to $STRESS_LOG"
