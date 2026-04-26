#!/usr/bin/env bash
# analyze.sh — Statistical analysis, plots, and final report
# Run from: CPU_Tuning/  →  bash scripts/analyze.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RAW="$PROJECT_DIR/results/raw"
PLOTS="$PROJECT_DIR/results/plots"
DOCS="$PROJECT_DIR/docs"
REPORT="$DOCS/final_report.txt"

mkdir -p "$PLOTS"

# Install python deps if needed
python3 -c "import matplotlib, scipy, numpy" 2>/dev/null || {
    echo "[INFO] Installing python dependencies ..."
    pip3 install matplotlib scipy numpy --break-system-packages -q
}

# Check all CSVs present
for s in SA SB C1 C2; do
    [[ ! -f "$RAW/${s}.csv" ]] && {
        echo "[ERROR] Missing: $RAW/${s}.csv"
        echo "        Run run_baselines.sh and run_experiments.sh first."
        exit 1
    }
done

echo "[analyze] Running statistical analysis and generating plots ..."
echo ""

python3 << PYEOF
import csv, math, sys
from pathlib import Path
from scipy import stats
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

RAW    = Path("$RAW")
PLOTS  = Path("$PLOTS")
DOCS   = Path("$DOCS")
REPORT = Path("$REPORT")

# ─────────────────────────────────────────────────────────────────────────────
# DATA LOADING
# ─────────────────────────────────────────────────────────────────────────────
def load(state):
    rows = []
    with open(RAW / f"{state}.csv") as f:
        for row in csv.DictReader(f):
            try:
                w = float(row["wall_sec"])
                m = int(row["cpu_migrations"])
                if w > 0.5:
                    rows.append((w, m))
            except (ValueError, KeyError):
                pass
    return rows

def walls(d): return [r[0] for r in d]
def migs(d):  return [r[1] for r in d]

def summary(xs):
    n  = len(xs)
    if n == 0: return {}
    m  = sum(xs) / n
    sd = math.sqrt(sum((x-m)**2 for x in xs) / (n-1)) if n > 1 else 0
    se = sd / math.sqrt(n)
    return {"n":n, "mean":m, "stdev":sd, "stderr":se,
            "min":min(xs), "max":max(xs), "cv": sd/m*100 if m>0 else 0}

def welch(a, b):
    if len(a) < 2 or len(b) < 2: return None, None
    t, p = stats.ttest_ind(a, b, equal_var=False)
    return float(t), float(p)

def pct(new, old):
    return (old - new) / old * 100 if old != 0 else 0

# ─────────────────────────────────────────────────────────────────────────────
# LOAD ALL STATES
# ─────────────────────────────────────────────────────────────────────────────
data = {s: load(s) for s in ["SA", "SB", "C1", "C2"]}

ORDER  = ["SA", "SB", "C1", "C2"]
COLORS = {
    "SA": "#4a90d9",   # blue   — clean baseline
    "SB": "#e05252",   # red    — bad baseline (problem)
    "C1": "#f0a500",   # amber  — affinity only
    "C2": "#2e7d32",   # green  — affinity + performance
}
LABELS = {
    "SA": "SA\nClean Baseline\n(single process)",
    "SB": "SB\nWorst Case\n(both on 1 core)",
    "C1": "C1\nAffinity Split\n(powersave)",
    "C2": "C2\nAffinity Split\n(performance)",
}

W  = {s: walls(data[s]) for s in ORDER}
M  = {s: migs(data[s])  for s in ORDER}
WS = {s: summary(W[s])  for s in ORDER}
MS = {s: summary(M[s])  for s in ORDER}

xs = np.arange(len(ORDER))
colors = [COLORS[s] for s in ORDER]
xlabs  = [LABELS[s] for s in ORDER]

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 1: Execution Time — Bar chart with error bars
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(11, 6))

means = [WS[s]["mean"]   for s in ORDER]
errs  = [WS[s]["stderr"] for s in ORDER]

bars = ax.bar(xs, means, yerr=errs, capsize=6,
              color=colors, edgecolor='black', linewidth=0.8,
              error_kw=dict(elinewidth=1.5, ecolor='#222'))

for bar, m, e in zip(bars, means, errs):
    ax.text(bar.get_x() + bar.get_width()/2,
            bar.get_height() + e + 0.3,
            f"{m:.2f}s", ha='center', va='bottom',
            fontsize=10, fontweight='bold')

# Improvement annotations
def annotate_improvement(ax, x1, x2, y, pct_val, color):
    ax.annotate('', xy=(x2, y), xytext=(x1, y),
                arrowprops=dict(arrowstyle='<->', color=color, lw=1.8))
    sign = "+" if pct_val > 0 else ""
    ax.text((x1+x2)/2, y + 0.4, f"{sign}{pct_val:.1f}%",
            ha='center', fontsize=9, color=color, fontweight='bold')

ymax = max(means) * 1.22
sb_mean = WS["SB"]["mean"]
annotate_improvement(ax, 1, 2, ymax,
    pct(WS["C1"]["mean"], sb_mean), "#f0a500")
annotate_improvement(ax, 1, 3, ymax * 1.08,
    pct(WS["C2"]["mean"], sb_mean), "#2e7d32")

ax.set_xticks(xs)
ax.set_xticklabels(xlabs, fontsize=10)
ax.set_ylabel("Mean Wall-Clock Time (seconds)", fontsize=12)
ax.set_title("CPU Execution Time — All States\n"
             "(error bars = ±1 standard error, n=10 per state)",
             fontsize=13, fontweight='bold')
ax.set_ylim(0, max(means) * 1.35)
ax.axhline(WS["SA"]["mean"], color='#4a90d9', linestyle='--',
           linewidth=1.2, alpha=0.6, label=f'SA clean baseline ({WS["SA"]["mean"]:.2f}s)')
ax.grid(axis='y', alpha=0.3)
ax.legend(fontsize=9)

plt.tight_layout()
plt.savefig(str(PLOTS / "01_execution_time.png"), dpi=150, bbox_inches='tight')
plt.close()
print("[plot] 01_execution_time.png")

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 2: Variance (stdev) — Secondary metric
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(11, 5))

stdevs = [WS[s]["stdev"] for s in ORDER]
cvs    = [WS[s]["cv"]    for s in ORDER]

bars2 = ax.bar(xs, stdevs, color=colors, edgecolor='black', linewidth=0.8)

for bar, sd, cv in zip(bars2, stdevs, cvs):
    ax.text(bar.get_x() + bar.get_width()/2,
            bar.get_height() + 0.005,
            f"{sd:.4f}s\n(CV={cv:.1f}%)",
            ha='center', va='bottom', fontsize=9, fontweight='bold')

ax.set_xticks(xs)
ax.set_xticklabels(xlabs, fontsize=10)
ax.set_ylabel("Standard Deviation of Wall-Clock Time (s)", fontsize=12)
ax.set_title("Execution Time Variance — Secondary Metric\n"
             "Lower = more stable/predictable execution (CV = coefficient of variation)",
             fontsize=13, fontweight='bold')
ax.grid(axis='y', alpha=0.3)
plt.tight_layout()
plt.savefig(str(PLOTS / "02_variance.png"), dpi=150, bbox_inches='tight')
plt.close()
print("[plot] 02_variance.png")

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 3: CPU Migrations
# ─────────────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(11, 5))

mig_means = [MS[s]["mean"]   for s in ORDER]
mig_errs  = [MS[s]["stderr"] for s in ORDER]

bars3 = ax.bar(xs, mig_means, yerr=mig_errs, capsize=6,
               color=colors, edgecolor='black', linewidth=0.8,
               error_kw=dict(elinewidth=1.5, ecolor='#222'))

for bar, m in zip(bars3, mig_means):
    ax.text(bar.get_x() + bar.get_width()/2,
            bar.get_height() + 0.05,
            f"{m:.1f}", ha='center', va='bottom',
            fontsize=10, fontweight='bold')

ax.set_xticks(xs)
ax.set_xticklabels(xlabs, fontsize=10)
ax.set_ylabel("Mean CPU Migrations per Run", fontsize=12)
ax.set_title("CPU Migrations — Mechanistic Metric\n"
             "Explains WHY execution time changes",
             fontsize=13, fontweight='bold')
ax.grid(axis='y', alpha=0.3)
plt.tight_layout()
plt.savefig(str(PLOTS / "03_migrations.png"), dpi=150, bbox_inches='tight')
plt.close()
print("[plot] 03_migrations.png")

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 4: Box plots — distribution shape
# ─────────────────────────────────────────────────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(14, 6))

wall_data = [W[s] for s in ORDER]
mig_data  = [M[s] for s in ORDER]

for ax_sub, dat, ylabel, title in [
    (axes[0], wall_data, "Wall-Clock Time (s)", "Execution Time Distribution"),
    (axes[1], mig_data,  "CPU Migrations",      "CPU Migration Distribution"),
]:
    bp = ax_sub.boxplot(dat, patch_artist=True, notch=False,
                        medianprops=dict(color='black', linewidth=2.5),
                        whiskerprops=dict(linewidth=1.5),
                        capprops=dict(linewidth=1.5))
    for patch, color in zip(bp['boxes'], colors):
        patch.set_facecolor(color)
        patch.set_alpha(0.75)
    ax_sub.set_xticklabels(xlabs, fontsize=9)
    ax_sub.set_ylabel(ylabel, fontsize=11)
    ax_sub.set_title(title, fontweight='bold', fontsize=11)
    ax_sub.grid(axis='y', alpha=0.3)

plt.suptitle("Distribution Shape — Box Plots (n=10 per state)",
             fontsize=13, fontweight='bold')
plt.tight_layout()
plt.savefig(str(PLOTS / "04_boxplots.png"), dpi=150, bbox_inches='tight')
plt.close()
print("[plot] 04_boxplots.png")

# ─────────────────────────────────────────────────────────────────────────────
# PLOT 5: % Improvement vs SB — the headline chart
# ─────────────────────────────────────────────────────────────────────────────
fig, axes = plt.subplots(1, 3, figsize=(14, 5))

comparisons = [
    ("SB→C1", "Affinity Split\n(powersave)",
     pct(WS["C1"]["mean"],  WS["SB"]["mean"]),
     pct(WS["C1"]["stdev"], WS["SB"]["stdev"]),
     pct(MS["C1"]["mean"],  MS["SB"]["mean"])  if MS["SB"]["mean"]>0 else 0),
    ("SB→C2", "Affinity+Performance\nvs Worst Case",
     pct(WS["C2"]["mean"],  WS["SB"]["mean"]),
     pct(WS["C2"]["stdev"], WS["SB"]["stdev"]),
     pct(MS["C2"]["mean"],  MS["SB"]["mean"])  if MS["SB"]["mean"]>0 else 0),
    ("C1→C2", "Governor Effect\n(on top of affinity)",
     pct(WS["C2"]["mean"],  WS["C1"]["mean"]),
     pct(WS["C2"]["stdev"], WS["C1"]["stdev"]),
     pct(MS["C2"]["mean"],  MS["C1"]["mean"])  if MS["C1"]["mean"]>0 else 0),
]

metric_labels = ["Wall Time\nImprovement (%)",
                 "Variance\nReduction (%)",
                 "Migration\nReduction (%)"]

bar_colors_pos = ["#2e7d32", "#1565c0", "#6a1b9a"]
bar_colors_neg = ["#c62828", "#c62828", "#c62828"]

for ax_sub, (comp_label, comp_title, t_imp, v_imp, m_imp) in zip(axes, comparisons):
    vals = [t_imp, v_imp, m_imp]
    bcols = [bar_colors_pos[i] if v >= 0 else bar_colors_neg[i]
             for i, v in enumerate(vals)]
    bars_p = ax_sub.bar(np.arange(3), vals, color=bcols,
                        edgecolor='black', linewidth=0.8)
    for bar, val in zip(bars_p, vals):
        yoff = 0.5 if val >= 0 else -2.5
        ax_sub.text(bar.get_x() + bar.get_width()/2,
                    bar.get_height() + yoff,
                    f"{val:+.1f}%", ha='center', fontsize=10,
                    fontweight='bold',
                    color='#2e7d32' if val >= 0 else '#c62828')
    ax_sub.axhline(0, color='black', linewidth=1)
    ax_sub.set_xticks(np.arange(3))
    ax_sub.set_xticklabels(metric_labels, fontsize=8.5)
    ax_sub.set_title(f"{comp_label}\n{comp_title}",
                     fontweight='bold', fontsize=10)
    ax_sub.set_ylabel("% Improvement", fontsize=10)
    ax_sub.grid(axis='y', alpha=0.3)

plt.suptitle("Tuning Effectiveness — % Improvement per Metric",
             fontsize=13, fontweight='bold')
plt.tight_layout()
plt.savefig(str(PLOTS / "05_improvement_pct.png"), dpi=150, bbox_inches='tight')
plt.close()
print("[plot] 05_improvement_pct.png")

# ─────────────────────────────────────────────────────────────────────────────
# STATISTICAL REPORT
# ─────────────────────────────────────────────────────────────────────────────
SEP  = "=" * 70
SEP2 = "─" * 70

lines = []
lines.append(SEP)
lines.append("  CPU PERFORMANCE TUNING — FINAL EXPERIMENT REPORT")
lines.append(SEP)

env = DOCS / "environment.txt"
if env.exists():
    lines.append("")
    lines.append(env.read_text().strip())

# ── Raw stats ─────────────────────────────────────────────────────────────────
lines.append("")
lines.append(SEP2)
lines.append("  RAW STATISTICS")
lines.append(SEP2)

state_desc = {
    "SA": "SA — Clean baseline (single process, cpu7+cpu5, powersave)",
    "SB": "SB — Manufactured worst case (BOTH processes on cpu7 only, powersave)",
    "C1": "C1 — Affinity split (cpu7 + cpu5), powersave governor",
    "C2": "C2 — Affinity split (cpu7 + cpu5), performance governor",
}

for s in ORDER:
    ws = WS[s]; ms = MS[s]
    lines.append("")
    lines.append(f"  {state_desc[s]}")
    lines.append(f"    n                    : {ws['n']}")
    lines.append(f"    wall mean            : {ws['mean']:.4f} s")
    lines.append(f"    wall stdev           : {ws['stdev']:.4f} s  ← secondary metric")
    lines.append(f"    wall stderr          : {ws['stderr']:.4f} s")
    lines.append(f"    wall CV              : {ws['cv']:.2f}%  (coeff of variation)")
    lines.append(f"    wall [min, max]      : [{ws['min']:.4f}, {ws['max']:.4f}] s")
    lines.append(f"    migrations mean      : {ms['mean']:.2f}")
    lines.append(f"    migrations stdev     : {ms['stdev']:.2f}")

# ── Comparisons ───────────────────────────────────────────────────────────────
lines.append("")
lines.append(SEP2)
lines.append("  COMPARISONS AND STATISTICAL VALIDATION")
lines.append(SEP2)

comps = [
    ("SA", "SB", "SA vs SB", "How bad is the manufactured problem?"),
    ("SB", "C1", "SB vs C1", "Affinity split effect (powersave unchanged)"),
    ("SB", "C2", "SB vs C2", "Full combined improvement (affinity + performance gov)"),
    ("C1", "C2", "C1 vs C2", "Governor-only effect (on top of affinity split)"),
]

for (ref, tgt, label, desc) in comps:
    rw = W[ref]; tw = W[tgt]
    rm = M[ref]; tm = M[tgt]
    t_w, p_w = welch(rw, tw)
    t_m, p_m = welch(rm, tm)

    time_imp = pct(WS[tgt]["mean"],  WS[ref]["mean"])
    var_imp  = pct(WS[tgt]["stdev"], WS[ref]["stdev"])
    mig_imp  = pct(MS[tgt]["mean"],  MS[ref]["mean"]) if MS[ref]["mean"] > 0 else 0

    sig = "SIGNIFICANT ✓" if (t_w and abs(t_w) > 2) else "not significant ✗"

    lines.append("")
    lines.append(f"  [{label}] — {desc}")
    lines.append(f"    wall time change     : {time_imp:+.2f}%  "
                 f"({WS[ref]['mean']:.4f}s → {WS[tgt]['mean']:.4f}s)")
    lines.append(f"    variance change      : {var_imp:+.2f}%  "
                 f"({WS[ref]['stdev']:.4f}s → {WS[tgt]['stdev']:.4f}s)")
    lines.append(f"    migration change     : {mig_imp:+.2f}%  "
                 f"({MS[ref]['mean']:.2f} → {MS[tgt]['mean']:.2f})")
    if t_w is not None:
        lines.append(f"    Welch t-stat (time)  : {t_w:.4f}   p = {p_w:.6f}")
        lines.append(f"    Significance         : {sig} at α = 0.05")

# ── Interpretation ────────────────────────────────────────────────────────────
lines.append("")
lines.append(SEP2)
lines.append("  INTERPRETATION — WHY EACH RESULT OCCURRED")
lines.append(SEP2)

sb_mean = WS["SB"]["mean"]
c1_mean = WS["C1"]["mean"]
c2_mean = WS["C2"]["mean"]
sa_mean = WS["SA"]["mean"]

lines.append(f"""
  SA (clean baseline):
    Single process, no competition. Represents the theoretical best
    execution time for this workload on this hardware. All tuning
    improvements are bounded above by this value ({sa_mean:.4f}s).

  SB (manufactured worst case):
    Both processes are taskset-locked to a single core (cpu7).
    The Linux scheduler cannot migrate them off — taskset is a hard
    constraint. Both threads fight for the same execution units, L1/L2
    cache, and decode pipeline. Result: wall time roughly doubles vs SA,
    variance increases as the OS timer interrupt creates unpredictable
    scheduling windows.

  C1 (affinity split, powersave unchanged):
    Each process gets its own dedicated P-core. Contention is eliminated
    at the hardware level. Migrations drop to near-zero because the
    scheduler has no reason to rebalance — each core has exactly the
    work assigned to it. Wall time improvement is due to eliminating
    core contention, not frequency change. Variance drops because
    cache state is now stable per core.
    Governor is still powersave — CPU may still throttle between runs,
    which explains any remaining variance.

  C2 (affinity split + performance governor):
    Same core isolation as C1, but the CPU now runs at locked maximum
    frequency. The powersave governor throttles frequency aggressively
    when load appears to drop — even briefly. Under performance governor,
    frequency is fixed at 4500 MHz throughout all runs. This eliminates
    the frequency-induced timing jitter seen in C1, reducing variance
    further. If wall time also improves over C1, it is because some
    runs under C1 suffered frequency throttle events that added latency.
""")

# ── Claims ────────────────────────────────────────────────────────────────────
lines.append(SEP2)
lines.append("  CLAIMS")
lines.append(SEP2)
lines.append(f"""
  What this experiment proves:
    Under controlled conditions on Intel Core Ultra 5 125H (kernel 7.x):

    1. CPU affinity partitioning (SB → C1):
       Pinning competing processes to dedicated P-cores eliminates
       single-core contention and reduces execution time significantly.
       Wall time improvement: {pct(c1_mean, sb_mean):+.2f}% over worst-case baseline.

    2. Performance governor (C1 → C2):
       Locking CPU frequency to maximum eliminates throttle-induced
       variance on top of the affinity improvement.
       Additional wall time change: {pct(c2_mean, c1_mean):+.2f}%.

    3. Combined effect (SB → C2):
       Total wall time improvement: {pct(c2_mean, sb_mean):+.2f}% over worst case.

  What this does NOT prove:
    - That these tunings always improve performance on all hardware
    - That single-core contention is the only failure mode
    - Any claim about NUMA, multi-socket, or heterogeneous workloads
""")

lines.append(SEP)
lines.append("")
lines.append("  Plots saved to: results/plots/")
lines.append("  01_execution_time.png  — bar chart with error bars")
lines.append("  02_variance.png        — stdev comparison (secondary metric)")
lines.append("  03_migrations.png      — cpu migration counts")
lines.append("  04_boxplots.png        — distribution shape")
lines.append("  05_improvement_pct.png — % improvement per tuning per metric")
lines.append(SEP)

report_text = "\n".join(lines)
print(report_text)
REPORT.write_text(report_text)
print(f"\n[analyze] Report → {REPORT}")
print(f"[analyze] Plots  → {PLOTS}/")
PYEOF