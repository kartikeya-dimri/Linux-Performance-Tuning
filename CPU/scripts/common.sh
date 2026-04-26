#!/usr/bin/env bash
# common.sh — Shared config and helpers (redesigned for scheduler pressure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKLOAD="$PROJECT_DIR/workload/prime"
RAW="$PROJECT_DIR/results/raw"
DOCS="$PROJECT_DIR/docs"

# ── Experiment parameters ─────────────────────────────────────
RUNS=10          # iterations per condition
PROCS=6          # competing processes (creates heavy scheduler pressure)
WAIT=5           # cooldown seconds between runs

# ── Core layout ───────────────────────────────────────────────
# SB: all PROCS crammed onto ONE core  → maximum contention
# C1: PROCS spread across TWO cores   → affinity relief
# C2: same as C1 + chrt real-time     → scheduler tuning
CORE_SB="7"         # single core for baseline contention
CORES_C1="5,7"      # two cores for affinity split
CORES_C2="5,7"      # two cores + real-time scheduling

# ── Preflight checks ─────────────────────────────────────────
preflight() {
    if [[ ! -x "$WORKLOAD" ]]; then
        echo "[ERROR] Binary missing: $WORKLOAD"
        echo "        Run: bash workload/build.sh"
        exit 1
    fi
    if ! command -v perf &>/dev/null; then
        echo "[ERROR] perf not found. Install linux-tools."
        exit 1
    fi
    if ! command -v chrt &>/dev/null; then
        echo "[ERROR] chrt not found. Install util-linux."
        exit 1
    fi
    mkdir -p "$RAW" "$DOCS"
}

# ── Single measurement ────────────────────────────────────────
# Usage: measure_run <csv> <run> <total> <fg_cores> <bg_cores> <mode>
#   mode: "normal" | "realtime"
#   bg_cores: cores for background workers (same as fg_cores for SB)
#
# Launches (PROCS-1) background workers, then measures one foreground process.
# Reports: wall_sec, context_switches of the foreground process only.
measure_run() {
    local csv="$1" run="$2" total="$3" fg_cores="$4" bg_cores="$5" mode="$6"

    echo -n "  Run $run/$total ... "

    local tmp_time tmp_perf
    tmp_time=$(mktemp)
    tmp_perf=$(mktemp)

    # ── Launch background workers ────────────────────────────
    local BG_PIDS=()
    for ((p=1; p<PROCS; p++)); do
        if [[ "$mode" == "realtime" ]]; then
            taskset -c "$bg_cores" chrt -r 98 "$WORKLOAD" 1 &>/dev/null &
        else
            taskset -c "$bg_cores" "$WORKLOAD" 1 &>/dev/null &
        fi
        BG_PIDS+=($!)
    done

    # ── Measure foreground process ───────────────────────────
    if [[ "$mode" == "realtime" ]]; then
        /usr/bin/time -f "%e" -o "$tmp_time" \
        perf stat -e context-switches -o "$tmp_perf" -- \
        taskset -c "$fg_cores" chrt -r 99 "$WORKLOAD" 1 \
        2>/dev/null
    else
        /usr/bin/time -f "%e" -o "$tmp_time" \
        perf stat -e context-switches -o "$tmp_perf" -- \
        taskset -c "$fg_cores" "$WORKLOAD" 1 \
        2>/dev/null
    fi

    # ── Reap background workers ──────────────────────────────
    for pid in "${BG_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # ── Parse results ────────────────────────────────────────
    local wall cs
    wall=$(cat "$tmp_time")
    cs=$(grep -E 'context-switches' "$tmp_perf" \
         | awk '{gsub(/,/,"",$1); print $1}')
    cs=${cs:-0}

    rm -f "$tmp_time" "$tmp_perf"

    echo "wall=${wall}s  ctx=${cs}"
    echo "${run},${wall},${cs}" >> "$csv"
}
