#!/bin/bash

WORKLOAD=$1
OUTPUT_DIR=${2:-.}

RUNTIME=90

echo "[+] Running memory workload: $WORKLOAD (output: $OUTPUT_DIR)"
mkdir -p "$OUTPUT_DIR"
STRESS_LOG="$OUTPUT_DIR/stress_ng.log"

# -----------------------------------------
# STRATEGY: allocate MORE than physical RAM so the kernel
# is FORCED to use swap regardless of swappiness setting.
# VM has 8 GB RAM → allocate 10–11 GB total across workers.
# swappiness=200 will thrash swap badly.
# swappiness=10  will minimize swapping → measurable improvement.
#
# Key: run stress-ng DIRECTLY (no systemd-run) so stdout
# is captured properly by tee.
# Use --vm-method walk-1d (valid method that touches every page)
# -----------------------------------------

case $WORKLOAD in

    # -----------------------------------------
    # ALLOC: 4 workers × 2500 MB = 10 GB > 8 GB RAM
    # ~2 GB MUST go to swap. swappiness determines HOW BADLY.
    # walk-1d writes linearly → every page genuinely touched
    # -----------------------------------------
    alloc)
        echo "[+] Allocating 10 GB across 4 workers (> 8 GB RAM) to force swap..."
        stress-ng --vm 4 \
                  --vm-bytes 2500M \
                  --vm-method walk-1d \
                  --metrics-brief \
                  --timeout ${RUNTIME}s \
                  2>&1 | tee "$STRESS_LOG"
        ;;

    # -----------------------------------------
    # CACHE: 4 cache workers + 2 VM workers
    # Cache workers thrash page cache; VM workers eat RAM.
    # Combined ~9 GB pressure on 8 GB system.
    # -----------------------------------------
    cache)
        echo "[+] Running cache thrash + anon pressure (combined ~9 GB)..."
        stress-ng --cache 4 \
                  --cache-size 1G \
                  --vm 2 \
                  --vm-bytes 1500M \
                  --vm-method walk-1d \
                  --metrics-brief \
                  --timeout ${RUNTIME}s \
                  2>&1 | tee "$STRESS_LOG"
        ;;

    # -----------------------------------------
    # MIX: 3 VM workers + 3 cache workers
    # VM: 3 × 2000 MB = 6 GB; cache: 3 × 1 GB = 3 GB
    # Total working set = 9 GB > 8 GB RAM
    # -----------------------------------------
    mix)
        echo "[+] Running mixed VM + cache workload (~9 GB total working set)..."
        stress-ng --vm 3 \
                  --vm-bytes 2000M \
                  --vm-method walk-1d \
                  --cache 3 \
                  --cache-size 1G \
                  --metrics-brief \
                  --timeout ${RUNTIME}s \
                  2>&1 | tee "$STRESS_LOG"
        ;;

    *)
        echo "Usage: $0 {alloc|cache|mix} [output_dir]"
        exit 1
        ;;
esac

echo "[+] Workload completed. Metrics: $STRESS_LOG"
