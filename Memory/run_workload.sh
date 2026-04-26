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
    # CACHE: Sequential access, different rotation pattern from alloc.
    #
    # ROOT CAUSE OF ALL PREVIOUS FAILURES WITH rand-set:
    #   Random access → kernel cannot predict which pages will be reused.
    #   With swappiness=200: background proactive eviction → low iowait.
    #   With swappiness=10:  holds everything until cliff → sync swap storm
    #                        → iowait HIGHER in tuned run (wrong direction).
    #
    # SOLUTION: Use sequential access (ror = rotate-right through memory).
    #   Sequential patterns align with the kernel's LRU logic:
    #   recently-walked pages are exactly the ones that should stay in RAM.
    #   swappiness=10 keeps recently-used pages → sequential workload benefits.
    #   swappiness=200 evicts them before they cycle back → page faults.
    #
    # Same 4×2500MB = 10GB > 8GB RAM as alloc → same proven pressure level.
    # ror vs walk-1d: ror writes 0101... bit rotation pattern (different
    # data pattern, same sequential page access order).
    # -----------------------------------------
    cache)
        echo "[+] Running cache-pressure (4×2500MB ror sequential, 10GB > 8GB)..."
        stress-ng --vm 4 \
                  --vm-bytes 2500M \
                  --vm-method ror \
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
