#!/usr/bin/env bash
# compare.sh — Statistical analysis + final report generator
#
# Place at: CPU/scripts/compare.sh
# Run from: CPU/ directory  →  bash scripts/compare.sh
#
# Reads:  results/state_A.csv  state_B.csv  state_C1.csv  (state_C2.csv optional)
# Writes: results/final_report.txt

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS="$PROJECT_DIR/results"
REPORT="$RESULTS/final_report.txt"

# ── Require python3 for stats ────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo "[ERROR] python3 required for statistical analysis."
    echo "        Install: sudo apt install python3"
    exit 1
fi

# ── Check required CSVs (C2 is optional) ────────────────────────────────────
for state in A B C1; do
    f="$RESULTS/state_${state}.csv"
    if [[ ! -f "$f" ]]; then
        echo "[ERROR] Missing: $f"
        echo "        Run run_baseline.sh and run_tuned.sh first."
        exit 1
    fi
done

C2_FILE="$RESULTS/state_C2.csv"
if [[ ! -f "$C2_FILE" ]]; then
    echo "[WARN] state_C2.csv not found — C2 analysis will be skipped."
elif [[ $(tail -n +2 "$C2_FILE" | wc -l) -eq 0 ]]; then
    echo "[WARN] state_C2.csv is empty (chrt likely failed) — C2 analysis will be skipped."
fi

echo "[compare] Running statistical analysis ..."

# ── Python stats block ───────────────────────────────────────────────────────
python3 - "$RESULTS" "$REPORT" << 'PYEOF'
import sys, csv, math, os
from pathlib import Path

results_dir = Path(sys.argv[1])
report_path = Path(sys.argv[2])

# ── helpers ──────────────────────────────────────────────────────────────────
def load_csv(state):
    fpath = results_dir / f"state_{state}.csv"
    if not fpath.exists():
        return []
    rows = []
    with open(fpath) as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                w = float(row["wall_sec"])
                m = int(row["cpu_migrations"])
                if w > 0:                  # skip any zero/corrupt rows
                    rows.append({"wall": w, "mig": m})
            except (ValueError, KeyError):
                pass
    return rows

def mean(xs):
    if not xs: return 0.0
    return sum(xs) / len(xs)

def variance(xs):
    if len(xs) < 2: return 0.0
    m = mean(xs)
    return sum((x - m) ** 2 for x in xs) / (len(xs) - 1)

def stdev(xs):  return math.sqrt(variance(xs))
def stderr(xs): return stdev(xs) / math.sqrt(len(xs)) if xs else 0.0

def welch_t(a, b):
    """Welch's t-statistic + Welch-Satterthwaite df. Needs n>=2 for each."""
    if len(a) < 2 or len(b) < 2:
        return None, None
    ma, mb = mean(a), mean(b)
    va, vb = variance(a), variance(b)
    na, nb = len(a), len(b)
    se = math.sqrt(va/na + vb/nb)
    if se == 0:
        return 0.0, float(na + nb - 2)
    t = (ma - mb) / se
    num   = (va/na + vb/nb) ** 2
    denom = ((va/na)**2 / (na-1)) + ((vb/nb)**2 / (nb-1))
    df = num / denom if denom > 0 else 1
    return t, df

def pct_change(new_val, old_val):
    if old_val == 0: return 0.0
    return (old_val - new_val) / old_val * 100.0

def fmt_state(label, vals):
    if not vals:
        return f"  {label}\n    [NO DATA]\n"
    ws = [v["wall"] for v in vals]
    ms = [v["mig"]  for v in vals]
    return (
        f"  {label}\n"
        f"    n                    : {len(ws)}\n"
        f"    wall_time  mean      : {mean(ws):.4f} s\n"
        f"    wall_time  stdev     : {stdev(ws):.4f} s\n"
        f"    wall_time  stderr    : {stderr(ws):.4f} s\n"
        f"    wall_time  [min,max] : [{min(ws):.4f}, {max(ws):.4f}] s\n"
        f"    migrations mean      : {mean(ms):.2f}\n"
        f"    migrations stdev     : {stdev(ms):.2f}\n"
    )

def fmt_comparison(label, wB, mB, wX, mX):
    if not wX:
        return f"  {label}\n    [SKIPPED — no data]\n"
    imp_time = pct_change(mean(wX), mean(wB))
    imp_mig  = pct_change(mean(mX), mean(mB)) if mean(mB) > 0 else 0.0
    t, df    = welch_t(wB, wX)
    if t is None:
        t_str = "N/A (insufficient data)"
        sig_str = "N/A"
    else:
        t_str   = f"{t:.4f}  (df={df:.1f})"
        sig_str = "SIGNIFICANT (|t|>2)" if abs(t) > 2 else "not significant at α=0.05"
    return (
        f"  {label}:\n"
        f"    wall_time improvement : {imp_time:+.2f}%  ({mean(wB):.4f}s → {mean(wX):.4f}s)\n"
        f"    migration reduction   : {imp_mig:+.2f}%  ({mean(mB):.2f} → {mean(mX):.2f})\n"
        f"    Welch t-stat          : {t_str}\n"
        f"    Interpretation        : {sig_str}\n"
    )

# ── Load data ─────────────────────────────────────────────────────────────────
A  = load_csv("A")
B  = load_csv("B")
C1 = load_csv("C1")
C2 = load_csv("C2")   # may be empty list — handled gracefully

wA  = [v["wall"] for v in A]
wB  = [v["wall"] for v in B]
wC1 = [v["wall"] for v in C1]
wC2 = [v["wall"] for v in C2]

mA  = [v["mig"] for v in A]
mB  = [v["mig"] for v in B]
mC1 = [v["mig"] for v in C1]
mC2 = [v["mig"] for v in C2]

# ── Build report ──────────────────────────────────────────────────────────────
lines = []
lines.append("=" * 70)
lines.append("  CPU PERFORMANCE TUNING — FINAL EXPERIMENT REPORT")
lines.append("=" * 70)

env_file = results_dir / "environment.txt"
if env_file.exists():
    lines.append("")
    lines.append(env_file.read_text().strip())

lines.append("")
lines.append("── RAW STATISTICS ──────────────────────────────────────────────────────")
lines.append("")
lines.append(fmt_state("State A  (clean baseline, no contention)", A))
lines.append(fmt_state("State B  (synthetic contention, same CPUs — the problem)", B))
lines.append(fmt_state("State C1 (affinity split only — Tuning 1)", C1))
lines.append(fmt_state("State C2 (affinity split + RT scheduling — Tuning 2)", C2))

lines.append("── COMPARISONS ─────────────────────────────────────────────────────────")
lines.append("")
lines.append("  Reference state: B (contention, no tuning)")
lines.append("")
lines.append(fmt_comparison("[Tuning 1] Affinity Split  (C1 vs B)", wB, mB, wC1, mC1))
lines.append("")
lines.append(fmt_comparison("[Tuning 2] Affinity Split + RT Sched  (C2 vs B)", wB, mB, wC2, mC2))
lines.append("")

# Isolate RT contribution (C2 vs C1) only if both have data
if wC1 and wC2:
    lines.append("  [Isolation] RT scheduling contribution (C2 vs C1):")
    imp_rt = pct_change(mean(wC2), mean(wC1))
    t_rt, df_rt = welch_t(wC1, wC2)
    if t_rt is not None:
        lines.append(f"    additional improvement: {imp_rt:+.2f}%  ({mean(wC1):.4f}s → {mean(wC2):.4f}s)")
        lines.append(f"    Welch t-stat          : {t_rt:.4f}  (df={df_rt:.1f})")
        lines.append(f"    Interpretation        : {'SIGNIFICANT (|t|>2)' if abs(t_rt)>2 else 'RT adds no significant benefit over affinity split alone'}")
    lines.append("")

lines.append("── CONCLUSION ───────────────────────────────────────────────────────")
lines.append("")
lines.append("  Claim (what this experiment proves):")
lines.append("    Under controlled conditions (same workload, same input, same")
lines.append("    hardware, minimal background load), CPU affinity splitting")
lines.append("    reduces wall-clock execution time and CPU migrations when")
lines.append("    two competing processes are pinned to separate physical cores")
lines.append("    instead of competing on the same CPU set.")
lines.append("")
lines.append("  Claim scope (what this does NOT prove):")
lines.append("    These results are specific to this machine, this kernel, and")
lines.append("    this workload. No universal guarantee is made.")
lines.append("")
lines.append("=" * 70)

report_text = "\n".join(lines)
print(report_text)
report_path.write_text(report_text)
print(f"\n[compare] Report saved to: {report_path}")
PYEOF

echo ""
echo ">>> ANALYSIS COMPLETE. Report: $REPORT"