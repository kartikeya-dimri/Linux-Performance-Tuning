#!/usr/bin/env bash
# run_baselines.sh — Collect SB (worst-case contention)
#
# SB design: PROCS processes all pinned to CORE_SB (one core)
#            → forces maximum context switching by the OS scheduler

set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
preflight

echo "============================================================"
echo "  BASELINE COLLECTION (SB)"
echo "  Design  : $PROCS processes pinned to a single core (cpu${CORE_SB})"
echo "  Runs    : $RUNS   Cooldown : ${WAIT}s"
echo "============================================================"
echo ""

# ── Environment snapshot ─────────────────────────────────────
{
    echo "=== Environment Snapshot ==="
    echo "Date         : $(date)"
    echo "Kernel       : $(uname -r)"
    echo "CPU          : $(lscpu | grep 'Model name' | sed 's/.*: *//')"
    echo "Total cores  : $(nproc)"
    echo ""
    echo "--- Experiment Design ---"
    echo "PROCS        : $PROCS  (competing processes per run)"
    echo "CORE_SB      : cpu${CORE_SB}  (all processes on one core)"
    echo "CORES_C1     : cpu${CORES_C1}  (processes spread, normal scheduler)"
    echo "CORES_C2     : cpu${CORES_C2}  (processes spread, chrt real-time)"
    echo ""
    echo "SB: Maximum contention — $PROCS processes share 1 core."
    echo "    OS must context-switch aggressively → many ctx switches."
    echo "C1: Affinity relief — spread across 2 cores."
    echo "    Expect: execution time ↓, context switches ↓"
    echo "C2: Scheduler tuning — chrt -r 99 (SCHED_RR real-time)."
    echo "    Expect: context switches ↓ significantly vs C1."
    echo "============================"
} | tee "$DOCS/environment.txt"

echo ""
echo ">>> SB: $PROCS processes all on cpu${CORE_SB} (maximum contention)"
echo ""

CSV="$RAW/SB.csv"
echo "run,wall_sec,context_switches" > "$CSV"

for ((i=1; i<=RUNS; i++)); do
    # Both fg and bg use same single core → worst-case contention
    measure_run "$CSV" "$i" "$RUNS" "${CORE_SB}" "${CORE_SB}" "normal"
    sleep "$WAIT"
done

echo ""
echo ">>> SB complete → $CSV"
echo ""
echo ">>> Now run: bash scripts/run_experiments.sh"
