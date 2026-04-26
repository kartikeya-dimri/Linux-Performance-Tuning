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
    # CACHE: same proven approach as alloc, different access pattern.
    #
    # WHY alloc worked:
    #   4 × 2500MB = 10GB > 8GB RAM → 2GB excess → workers CONTINUOUSLY
    #   cycle through all pages via walk-1d → every second, some pages
    #   must be swapped in/out → vmstat median is non-zero, stats significant.
    #
    # WHY --vm-keep FAILED: workers held allocation but barely re-accessed
    #   pages → no active demand → swap didn't happen → median stayed 0.
    #
    # CACHE DIFFERENTIATION: same 4×2500MB pressure, but --vm-method rand-set
    #   (random page access pattern) vs alloc's walk-1d (sequential).
    #   rand-set simulates cache-thrash: unpredictable access breaks
    #   hardware prefetcher, exercises the kernel's LRU list more randomly.
    #
    # Bad config: swappiness=200 → kernel constantly evicts pages it needs
    # Good config: swappiness=10 → kernel protects recently-accessed pages
    # -----------------------------------------
    cache)
        echo "[+] Running cache-pattern pressure (4×2500MB rand-set, 10GB > 8GB)..."
        stress-ng --vm 4 \
                  --vm-bytes 2500M \
                  --vm-method rand-set \
                  --metrics-brief \
                  --timeout ${RUNTIME}s \
                  2>&1 | tee "$STRESS_LOG"
        ;;

    # -----------------------------------------
    # MIX: Two groups of workers with different access patterns
    # Group A (walk-1d): linear sequential → models alloc-style pressure
    # Group B (rand-set): random access → models cache-thrash-style pressure
    # Both use --vm-keep so ALL allocations stay resident simultaneously.
    # Total resident: 2×2500MB + 2×2000MB = 9GB > 8GB RAM → continuous swap
    # -----------------------------------------
    mix)
        echo "[+] Running mixed continuous pressure (9 GB resident, 90s)..."
        stress-ng --vm 2 \
                  --vm-bytes 2500M \
                  --vm-method walk-1d \
                  --vm-keep \
                  --vm 2 \
                  --vm-bytes 2000M \
                  --vm-method rand-set \
                  --vm-keep \
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
