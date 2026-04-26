#!/usr/bin/env bash
# common.sh — Shared config and helpers
# Sourced by all run_*.sh scripts. Never run directly.

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKLOAD="$PROJECT_DIR/workload/prime"
RAW="$PROJECT_DIR/results/raw"
DOCS="$PROJECT_DIR/docs"

# ── Experiment config ─────────────────────────────────────────────────────────
RUNS=10         # runs per state
THREADS=2       # threads per prime instance
WAIT=3          # seconds cooldown between runs
CORE_A=7        # primary P-core (both processes here in SB)
CORE_B=5        # secondary P-core (used in split states C1, C2)

# ── Preflight checks ──────────────────────────────────────────────────────────
preflight() {
    if [[ ! -x "$WORKLOAD" ]]; then
        echo "[ERROR] Binary missing: $WORKLOAD"
        echo "        Run: bash workload/build.sh"
        exit 1
    fi
    if ! command -v perf &>/dev/null; then
        echo "[ERROR] perf not found."
        echo "        sudo apt install linux-tools-common linux-tools-generic linux-tools-\$(uname -r)"
        exit 1
    fi
    # Check perf works (paranoid setting)
    if ! perf stat -e cpu-migrations -- true 2>/dev/null; then
        echo "[ERROR] perf blocked. Fix with:"
        echo "        sudo sysctl -w kernel.perf_event_paranoid=1"
        exit 1
    fi
    mkdir -p "$RAW" "$DOCS"
}

# ── Governor control ──────────────────────────────────────────────────────────
set_governor() {
    local gov="$1"
    echo "[env] Setting governor: $gov ..."
    sudo cpupower frequency-set -g "$gov" 2>/dev/null \
        && echo "[env] Governor set: $gov" \
        || echo "[WARN] cpupower failed — governor may not have changed"
    # Verify
    local actual
    actual=$(cat /sys/devices/system/cpu/cpu${CORE_A}/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
    echo "[env] Verified governor on cpu${CORE_A}: $actual"
    if [[ "$actual" != "$gov" ]]; then
        echo "[ERROR] Governor did not switch to $gov — got $actual. Aborting."
        exit 1
    fi
}

current_governor() {
    cat /sys/devices/system/cpu/cpu${CORE_A}/cpufreq/scaling_governor 2>/dev/null || echo "unknown"
}

# ── Core measurement ──────────────────────────────────────────────────────────
# Runs a single foreground process with optional background contention process
# Usage: measure_run CSV RUN TOTAL BG_CORE FG_CORE
#   BG_CORE="" means no background process (SA case)
#   BG_CORE=N  means launch background process on core N first
measure_run() {
    local csv="$1" run="$2" total="$3" bg_core="$4" fg_core="$5"

    echo -n "  Run $run/$total ... "

    local tmp_time; tmp_time=$(mktemp)
    local tmp_perf; tmp_perf=$(mktemp)

    # Launch background contention process if requested
    local BG_PID=""
    if [[ -n "$bg_core" ]]; then
        taskset -c "$bg_core" "$WORKLOAD" "$THREADS" &>/dev/null &
        BG_PID=$!
    fi

    # Measure foreground process
    /usr/bin/time -f "%e" -o "$tmp_time" \
        perf stat -e cpu-migrations -o "$tmp_perf" -- \
        taskset -c "$fg_core" "$WORKLOAD" "$THREADS" \
        2>/dev/null

    # Wait for background to finish if it was launched
    if [[ -n "$BG_PID" ]]; then
        wait "$BG_PID" 2>/dev/null || true
    fi

    local wall mig
    wall=$(cat "$tmp_time")
    mig=$(grep -E 'cpu-migrations' "$tmp_perf" \
          | awk '{gsub(/,/,"",$1); print $1}')
    mig=${mig:-0}
    rm -f "$tmp_time" "$tmp_perf"

    echo "wall=${wall}s  migrations=${mig}"
    echo "${run},${wall},${mig}" >> "$csv"
}