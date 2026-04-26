#!/usr/bin/env bash
# measure.sh — Core measurement helper
# NOT meant to be run directly. Sourced by run_baseline.sh and run_tuned.sh
#
# Exports two functions:
#   measure_single  CMD...   → prints wall_time and cpu_migrations to stdout
#   run_n_times     N CMD... → runs measure_single N times, writes CSV to $OUT_FILE

# --------------------------------------------------------------------------
# measure_single: run a command, capture wall time + cpu migrations
# Output (stdout): "wall_sec=X.XXXX migrations=Y"
# --------------------------------------------------------------------------
measure_single() {
    local cmd=("$@")

    # Temp files for outputs
    local tmp_time; tmp_time=$(mktemp)
    local tmp_perf; tmp_perf=$(mktemp)

    # Run with perf stat capturing cpu-migrations, redirect program stderr elsewhere
    /usr/bin/time -f "%e" -o "$tmp_time" \
        perf stat -e cpu-migrations -o "$tmp_perf" -- "${cmd[@]}" \
        2>/dev/null

    # Parse wall time
    local wall_sec
    wall_sec=$(cat "$tmp_time")

    # Parse cpu-migrations from perf output
    # perf prints lines like: "       12      cpu-migrations"
    local migrations
    migrations=$(grep -E 'cpu-migrations' "$tmp_perf" \
                 | awk '{gsub(/,/,"",$1); print $1}')
    migrations=${migrations:-0}

    rm -f "$tmp_time" "$tmp_perf"

    echo "wall_sec=${wall_sec} migrations=${migrations}"
}

# --------------------------------------------------------------------------
# run_n_times: run measure_single N times and append to OUT_FILE as CSV
# Args: $1=N, rest=command
# Expects OUT_FILE to be set by caller
# --------------------------------------------------------------------------
run_n_times() {
    local n="$1"; shift
    local cmd=("$@")
    local run wall mig

    for ((run=1; run<=n; run++)); do
        echo -n "  Run $run/$n ... "
        result=$(measure_single "${cmd[@]}")
        wall=$(echo "$result" | grep -oP 'wall_sec=\K[0-9.]+')
        mig=$(echo "$result"  | grep -oP 'migrations=\K[0-9]+')
        echo "wall=${wall}s  migrations=${mig}"
        echo "${run},${wall},${mig}" >> "$OUT_FILE"
    done
}
