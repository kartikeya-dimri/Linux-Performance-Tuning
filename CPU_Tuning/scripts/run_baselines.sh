#!/usr/bin/env bash
# run_baselines.sh — Collect SA (clean) and SB (worst-case contention)
#
# SA: single process on CORE_A+CORE_B, powersave governor
#     → true clean baseline, no competition
#
# SB: TWO processes BOTH pinned to CORE_A only, powersave governor
#     → deliberate worst case: both fight for one core
#     → scheduler cannot rebalance (taskset locks them)
#     → this is the manufactured problem we will fix
#
# Run from: CPU_Tuning/  →  bash scripts/run_baselines.sh

set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
preflight

echo "============================================================"
echo "  BASELINE COLLECTION"
echo "  Primary P-core   : cpu${CORE_A}"
echo "  Secondary P-core : cpu${CORE_B}"
echo "  Runs : $RUNS   Threads : $THREADS   Cooldown : ${WAIT}s"
echo "============================================================"
echo ""

# ── Set powersave governor for all baselines ──────────────────────────────────
set_governor powersave
echo ""

# ── Environment snapshot ──────────────────────────────────────────────────────
{
    echo "=== Environment Snapshot ==="
    echo "Date         : $(date)"
    echo "Kernel       : $(uname -r)"
    echo "CPU          : $(lscpu | grep 'Model name' | sed 's/.*: *//')"
    echo "Total cores  : $(nproc)"
    echo "CORE_A       : cpu${CORE_A} — $(cat /sys/devices/system/cpu/cpu${CORE_A}/cpufreq/cpuinfo_max_freq 2>/dev/null || echo '?') kHz max"
    echo "CORE_B       : cpu${CORE_B} — $(cat /sys/devices/system/cpu/cpu${CORE_B}/cpufreq/cpuinfo_max_freq 2>/dev/null || echo '?') kHz max"
    echo "Governor     : $(current_governor)"
    echo "RT throttle  : $(cat /proc/sys/kernel/sched_rt_runtime_us)"
    echo "perf_paranoid: $(cat /proc/sys/kernel/perf_event_paranoid)"
    echo "Runs         : $RUNS"
    echo "Threads      : $THREADS"
    echo "UPPER_LIMIT  : 25000000"
    echo ""
    echo "--- Experiment Design ---"
    echo "SA : single process, cpu${CORE_A}+cpu${CORE_B}, powersave  → clean baseline"
    echo "SB : TWO processes, BOTH on cpu${CORE_A} only, powersave   → manufactured worst case"
    echo "C1 : TWO processes, split cpu${CORE_A}+cpu${CORE_B}, powersave → affinity only"
    echo "C2 : TWO processes, split cpu${CORE_A}+cpu${CORE_B}, performance → affinity + governor"
    echo "============================"
} | tee "$DOCS/environment.txt"
echo ""

# ── SA: Clean single-process baseline ────────────────────────────────────────
echo "─────────────────────────────────────────────────────────────"
echo ">>> SA: Clean baseline"
echo "    One process on cpu${CORE_A}+cpu${CORE_B}, powersave, no contention"
echo "─────────────────────────────────────────────────────────────"

CSV="$RAW/SA.csv"
echo "run,wall_sec,cpu_migrations" > "$CSV"

for ((i=1; i<=RUNS; i++)); do
    # No background process — pass empty string for bg_core
    measure_run "$CSV" "$i" "$RUNS" "" "${CORE_A}"
    sleep "$WAIT"
done

echo ""
echo ">>> SA complete → $CSV"
echo ""

# ── SB: Manufactured worst case — both on ONE core ───────────────────────────
echo "─────────────────────────────────────────────────────────────"
echo ">>> SB: Manufactured worst case"
echo "    BOTH processes pinned to cpu${CORE_A} only (single core contention)"
echo "    Scheduler cannot migrate them — taskset locks to cpu${CORE_A}"
echo "    This is deliberately bad to prove tuning works"
echo "─────────────────────────────────────────────────────────────"

CSV="$RAW/SB.csv"
echo "run,wall_sec,cpu_migrations" > "$CSV"

for ((i=1; i<=RUNS; i++)); do
    # Both BG and FG on CORE_A — severe single-core contention
    measure_run "$CSV" "$i" "$RUNS" "${CORE_A}" "${CORE_A}"
    sleep "$WAIT"
done

echo ""
echo ">>> SB complete → $CSV"
echo ""
echo ">>> BASELINES COMPLETE."
echo "    Expected: SB wall time should be ~2x SA"
echo "    Now run: bash scripts/run_experiments.sh"