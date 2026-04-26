#!/usr/bin/env bash
# run_experiments.sh — Tuning cases C1 and C2
#
# C1: Affinity split only (powersave governor unchanged)
#     BG on CORE_A, FG on CORE_B
#     Isolates: does splitting cores fix contention regardless of governor?
#
# C2: Affinity split + performance governor
#     Same split as C1, but governor switched to performance
#     Isolates: does governor add further improvement on top of affinity?
#
# Run from: CPU_Tuning/  →  bash scripts/run_experiments.sh

set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
preflight

if [[ ! -f "$RAW/SB.csv" ]]; then
    echo "[ERROR] SB.csv not found. Run run_baselines.sh first."
    exit 1
fi

echo "============================================================"
echo "  TUNING EXPERIMENTS"
echo "  CORE_A : cpu${CORE_A}   CORE_B : cpu${CORE_B}"
echo "  Runs : $RUNS   Threads : $THREADS   Cooldown : ${WAIT}s"
echo "============================================================"
echo ""

# ── C1: Affinity split only — powersave governor ─────────────────────────────
echo "─────────────────────────────────────────────────────────────"
echo ">>> C1: Affinity split, powersave governor"
echo "    BG process → cpu${CORE_A}   FG process → cpu${CORE_B}"
echo "    Each process owns a dedicated P-core"
echo "    Governor unchanged from SB (powersave)"
echo "─────────────────────────────────────────────────────────────"

set_governor powersave
echo ""

CSV="$RAW/C1.csv"
echo "run,wall_sec,cpu_migrations" > "$CSV"

for ((i=1; i<=RUNS; i++)); do
    measure_run "$CSV" "$i" "$RUNS" "${CORE_A}" "${CORE_B}"
    sleep "$WAIT"
done

echo ""
echo ">>> C1 complete → $CSV"
echo ""

# ── C2: Affinity split + performance governor ─────────────────────────────────
echo "─────────────────────────────────────────────────────────────"
echo ">>> C2: Affinity split + performance governor"
echo "    BG process → cpu${CORE_A}   FG process → cpu${CORE_B}"
echo "    Governor switched to performance"
echo "    Tests: does governor add further benefit on top of affinity?"
echo "─────────────────────────────────────────────────────────────"

set_governor performance
echo ""

CSV="$RAW/C2.csv"
echo "run,wall_sec,cpu_migrations" > "$CSV"

for ((i=1; i<=RUNS; i++)); do
    measure_run "$CSV" "$i" "$RUNS" "${CORE_A}" "${CORE_B}"
    sleep "$WAIT"
done

echo ""
echo ">>> C2 complete → $CSV"
echo ""

# ── Restore governor ──────────────────────────────────────────────────────────
set_governor powersave
echo ""
echo ">>> ALL EXPERIMENTS COMPLETE. Governor restored to powersave."
echo "    Now run: bash scripts/analyze.sh"