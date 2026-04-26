#!/bin/bash

WORKLOAD=$1
RUNTIME=90

echo "[+] Running memory workload: $WORKLOAD"

case $WORKLOAD in

    # -----------------------------------------
    # ALLOC — Anonymous memory pressure
    # Simulates: JVM heap, malloc-heavy apps
    # 4 workers each allocating 75% of total RAM
    # repeatedly writing and freeing pages
    # -----------------------------------------
    alloc)
        stress-ng --vm 4 \
                  --vm-bytes 75% \
                  --vm-method all \
                  --timeout ${RUNTIME}s \
                  --metrics-brief
        ;;

    # -----------------------------------------
    # CACHE — Page cache + CPU cache thrash
    # Simulates: database buffer pool, file servers
    # 4 workers thrashing L1/L2/L3 + page cache
    # -----------------------------------------
    cache)
        stress-ng --cache 4 \
                  --cache-size 256M \
                  --timeout ${RUNTIME}s \
                  --metrics-brief
        ;;

    # -----------------------------------------
    # MIX — Combined anonymous + cache pressure
    # Simulates: real-world mixed memory workload
    # 2 VM workers + 2 cache workers simultaneously
    # -----------------------------------------
    mix)
        stress-ng --vm 2 \
                  --vm-bytes 50% \
                  --vm-method all \
                  --cache 2 \
                  --cache-size 256M \
                  --timeout ${RUNTIME}s \
                  --metrics-brief
        ;;

    *)
        echo "Usage: $0 {alloc|cache|mix}"
        exit 1
        ;;
esac

echo "[+] Workload completed."
