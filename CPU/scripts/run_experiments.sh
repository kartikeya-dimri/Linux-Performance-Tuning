#!/usr/bin/env bash
# run_experiments.sh — C1 (affinity) and C2 (affinity + chrt real-time)
#
# C1: Same PROCS processes, spread across CORES_C1 (two cores)
#     → less contention, fewer context switches, faster execution
#
# C2: Same as C1, but foreground + background use chrt -r 99/98 (SCHED_RR)
#     → real-time class dramatically reduces involuntary preemptions
#     → context switches drop significantly vs C1

set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
preflight

if [[ ! -f "$RAW/SB.csv" ]]; then
    echo "[ERROR] SB.csv not found. Run run_baselines.sh first."
    exit 1
fi

echo "============================================================"
echo "  EXPERIMENTS: Affinity (C1) vs Affinity + chrt (C2)"
echo "  Processes : $PROCS   Cooldown : ${WAIT}s"
echo "============================================================"
echo ""

# ── C1: Affinity split only ───────────────────────────────────
echo ">>> C1: $PROCS processes spread across cpu${CORES_C1} (affinity only)"
echo ""

CSV="$RAW/C1.csv"
echo "run,wall_sec,context_switches" > "$CSV"

for ((i=1; i<=RUNS; i++)); do
    measure_run "$CSV" "$i" "$RUNS" "${CORES_C1}" "${CORES_C1}" "normal"
    sleep "$WAIT"
done

echo ""
echo ">>> C1 complete → $CSV"
echo ""

# ── C2: Affinity + chrt real-time ────────────────────────────
echo ">>> C2: $PROCS processes on cpu${CORES_C2} + chrt SCHED_RR (real-time)"
echo "        Foreground: chrt -r 99  |  Background workers: chrt -r 98"
echo ""

# Warn if not running as root (chrt -r requires CAP_SYS_NICE or root)
if [[ $EUID -ne 0 ]]; then
    echo "[WARN] Not running as root. chrt -r (SCHED_RR) may fail."
    echo "       Try: sudo bash scripts/run_experiments.sh"
    echo "       Or:  sudo setcap cap_sys_nice+ep \$(which chrt)"
    echo ""
fi

CSV="$RAW/C2.csv"
echo "run,wall_sec,context_switches" > "$CSV"

for ((i=1; i<=RUNS; i++)); do
    measure_run "$CSV" "$i" "$RUNS" "${CORES_C2}" "${CORES_C2}" "realtime"
    sleep "$WAIT"
done

echo ""
echo ">>> C2 complete → $CSV"
echo ""
echo ">>> Now run: bash scripts/analyze.sh"
