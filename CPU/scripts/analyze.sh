#!/usr/bin/env bash
# analyze.sh — Stats + plots (bar, box, distribution) + Welch t-test report

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RAW="$PROJECT_DIR/results/raw"
PLOTS="$PROJECT_DIR/results/plots"
DOCS="$PROJECT_DIR/docs"
REPORT="$DOCS/final_report.txt"

mkdir -p "$PLOTS"

python3 << PYEOF
import csv, math
from pathlib import Path
from scipy import stats
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

RAW   = Path("$RAW")
PLOTS = Path("$PLOTS")
REPORT = Path("$REPORT")

# ── Helpers ──────────────────────────────────────────────────
def load(state):
    rows = []
    with open(RAW / f"{state}.csv") as f:
        for row in csv.DictReader(f):
            rows.append((float(row["wall_sec"]), int(row["context_switches"])))
    return rows

def walls(d): return [r[0] for r in d]
def ctx(d):   return [r[1] for r in d]

def summary(xs):
    n  = len(xs)
    m  = sum(xs) / n
    sd = math.sqrt(sum((x - m)**2 for x in xs) / (n - 1))
    se = sd / math.sqrt(n)
    return m, sd, se

def welch(a, b):
    t, p = stats.ttest_ind(a, b, equal_var=False)
    # Cohen's d
    mean_diff = abs(np.mean(a) - np.mean(b))
    pooled_sd = math.sqrt((np.std(a, ddof=1)**2 + np.std(b, ddof=1)**2) / 2)
    d = mean_diff / pooled_sd if pooled_sd > 0 else 0
    return t, p, d

LABELS = ["SB", "C1", "C2"]
DATA   = {k: load(k) for k in LABELS}
W      = {k: walls(DATA[k]) for k in LABELS}
C      = {k: ctx(DATA[k])   for k in LABELS}

COLORS = {"SB": "#e05252", "C1": "#5284e0", "C2": "#52c07a"}

stats_w = {k: summary(W[k]) for k in LABELS}
stats_c = {k: summary(C[k]) for k in LABELS}

# ── Plot style ────────────────────────────────────────────────
plt.rcParams.update({
    "figure.dpi": 150,
    "axes.spines.top":   False,
    "axes.spines.right": False,
    "font.size": 11,
})

def bar_with_error(ax, values, errors, labels, ylabel, title, colors):
    x = np.arange(len(labels))
    bars = ax.bar(x, values, yerr=errors, capsize=6,
                  color=[colors[l] for l in labels],
                  edgecolor="white", linewidth=0.8,
                  error_kw=dict(elinewidth=1.5, ecolor="#333"))
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=12)
    ax.set_ylabel(ylabel)
    ax.set_title(title, fontsize=13, fontweight="bold", pad=10)
    for bar, val in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + max(errors)*0.05,
                f"{val:.2f}", ha="center", va="bottom", fontsize=10, color="#333")

# ── Plot 1: Execution Time Bar ────────────────────────────────
fig, ax = plt.subplots(figsize=(7, 5))
means = [stats_w[k][0] for k in LABELS]
sems  = [stats_w[k][2] for k in LABELS]
bar_with_error(ax, means, sems, LABELS, "Wall Time (s)",
               "Execution Time by Condition\n(mean ± SE, 10 runs each)", COLORS)
plt.tight_layout()
plt.savefig(PLOTS / "1_execution_time_bar.png")
plt.close()

# ── Plot 2: Context Switches Bar ──────────────────────────────
fig, ax = plt.subplots(figsize=(7, 5))
c_means = [stats_c[k][0] for k in LABELS]
c_sems  = [stats_c[k][2] for k in LABELS]
bar_with_error(ax, c_means, c_sems, LABELS, "Context Switches",
               "Context Switches by Condition\n(mean ± SE, 10 runs each)", COLORS)
plt.tight_layout()
plt.savefig(PLOTS / "2_context_switches_bar.png")
plt.close()

# ── Plot 3: Execution Time Box (log scale) ───────────────────
# Log scale is essential here: SB SD=0.018s is invisible on a linear
# 0–45s axis, so boxes collapse to dots. Log scale makes all three
# distributions visible simultaneously.
fig, ax = plt.subplots(figsize=(7, 5))
bp = ax.boxplot([W[k] for k in LABELS], tick_labels=LABELS,
                patch_artist=True, medianprops=dict(color="white", linewidth=2))
for patch, label in zip(bp["boxes"], LABELS):
    patch.set_facecolor(COLORS[label])
    patch.set_alpha(0.85)
for flier in bp["fliers"]:
    flier.set(marker="o", markerfacecolor="#555", markersize=5, alpha=0.6)
ax.set_yscale("log")
ax.set_ylabel("Wall Time (s)  [log scale]")
ax.set_title("Execution Time Distribution  (log scale)\n(box = IQR, whiskers = 1.5×IQR)",
             fontsize=13, fontweight="bold", pad=10)
# Annotate mean on each box so values are readable on log axis
for i, k in enumerate(LABELS, start=1):
    ax.text(i, np.mean(W[k]), f"{np.mean(W[k]):.2f}s",
            ha="center", va="bottom", fontsize=9, color="#333",
            bbox=dict(boxstyle="round,pad=0.2", fc="white", alpha=0.7, ec="none"))
plt.tight_layout()
plt.savefig(PLOTS / "3_execution_time_box.png")
plt.close()

# ── Plot 4: Context Switches Box ──────────────────────────────
fig, ax = plt.subplots(figsize=(7, 5))
bp = ax.boxplot([C[k] for k in LABELS], tick_labels=LABELS,
                patch_artist=True, medianprops=dict(color="white", linewidth=2))
for patch, label in zip(bp["boxes"], LABELS):
    patch.set_facecolor(COLORS[label])
    patch.set_alpha(0.85)
for flier in bp["fliers"]:
    flier.set(marker="o", markerfacecolor="#555", markersize=5, alpha=0.6)
ax.set_ylabel("Context Switches")
ax.set_title("Context Switches Distribution\n(box = IQR, whiskers = 1.5×IQR)",
             fontsize=13, fontweight="bold", pad=10)
plt.tight_layout()
plt.savefig(PLOTS / "4_context_switches_box.png")
plt.close()

# ── Plot 5: Execution Time KDE ────────────────────────────────
# Each condition has very different spread (SB SD=0.018, C1 SD=0.99, C2 SD=0.84)
# Use per-condition bandwidth to avoid the spike/flat issue.
fig, ax = plt.subplots(figsize=(8, 5))
all_w = np.concatenate([W[k] for k in LABELS])
x_min, x_max = all_w.min() - 1, all_w.max() + 1
xs = np.linspace(x_min, x_max, 600)
for k in LABELS:
    data = np.array(W[k])
    # Silverman's rule but floor bandwidth at 0.3s so SB doesn't spike to infinity
    bw = max(stats.gaussian_kde(data).factor * data.std(), 0.3)
    kde = stats.gaussian_kde(data, bw_method=bw / data.std())
    ys  = kde(xs)
    ax.plot(xs, ys, label=k, color=COLORS[k], linewidth=2.2)
    ax.fill_between(xs, ys, alpha=0.12, color=COLORS[k])
    ax.axvline(data.mean(), color=COLORS[k], linestyle="--", linewidth=1, alpha=0.7)
ax.set_xlabel("Wall Time (s)")
ax.set_ylabel("Density")
ax.set_title("Execution Time Distribution (KDE)\n(dashed = mean)",
             fontsize=13, fontweight="bold", pad=10)
ax.legend()
plt.tight_layout()
plt.savefig(PLOTS / "5_execution_time_kde.png")
plt.close()

# ── Plot 6: Context Switches KDE ─────────────────────────────
fig, ax = plt.subplots(figsize=(8, 5))
for k in LABELS:
    data = np.array(C[k], dtype=float)
    if data.std() == 0:
        ax.axvline(data[0], color=COLORS[k], linewidth=2.2, label=f"{k} (constant={int(data[0])})")
        continue
    kde = stats.gaussian_kde(data, bw_method="scott")
    xs  = np.linspace(max(0, data.min() - data.std()), data.max() + data.std(), 300)
    ax.plot(xs, kde(xs), label=k, color=COLORS[k], linewidth=2.2)
    ax.fill_between(xs, kde(xs), alpha=0.12, color=COLORS[k])
    ax.axvline(data.mean(), color=COLORS[k], linestyle="--", linewidth=1, alpha=0.7)
ax.set_xlabel("Context Switches")
ax.set_ylabel("Density")
ax.set_title("Context Switches Distribution (KDE)\n(dashed = mean)",
             fontsize=13, fontweight="bold", pad=10)
ax.legend()
plt.tight_layout()
plt.savefig(PLOTS / "6_context_switches_kde.png")
plt.close()

# ── Statistical tests ─────────────────────────────────────────
t_sb_c1_w, p_sb_c1_w, d_sb_c1_w = welch(W["SB"], W["C1"])
t_c1_c2_w, p_c1_c2_w, d_c1_c2_w = welch(W["C1"], W["C2"])
t_sb_c1_c, p_sb_c1_c, d_sb_c1_c = welch(C["SB"], C["C1"])
t_c1_c2_c, p_c1_c2_c, d_c1_c2_c = welch(C["C1"], C["C2"])

def sig(p): return "SIGNIFICANT ✓" if p < 0.05 else "NOT SIGNIFICANT ✗"
def pct(a, b): return ((b - a) / a) * 100

# ── Final report ──────────────────────────────────────────────
report = f"""
╔══════════════════════════════════════════════════════════════╗
║              CPU TUNING EXPERIMENT — FINAL REPORT            ║
╚══════════════════════════════════════════════════════════════╝

Design
  Workload : prime (count primes to 25,000,000)
  Processes: {len(W["SB"])} runs × {6} competing processes per condition
  SB  : {6} processes → single core  (maximum contention)
  C1  : {6} processes → two cores    (affinity tuning)
  C2  : {6} processes → two cores    (affinity + chrt SCHED_RR)

──────────────────────────────────────────────────────────────
 EXECUTION TIME (wall seconds)
──────────────────────────────────────────────────────────────
  SB  : {stats_w["SB"][0]:.3f}s  ± {stats_w["SB"][1]:.3f}s SD
  C1  : {stats_w["C1"][0]:.3f}s  ± {stats_w["C1"][1]:.3f}s SD   ({pct(stats_w["SB"][0], stats_w["C1"][0]):+.1f}% vs SB)
  C2  : {stats_w["C2"][0]:.3f}s  ± {stats_w["C2"][1]:.3f}s SD   ({pct(stats_w["SB"][0], stats_w["C2"][0]):+.1f}% vs SB)

  Welch t-test (SB vs C1) : t={t_sb_c1_w:.3f}  p={p_sb_c1_w:.6f}  d={d_sb_c1_w:.3f}  → {sig(p_sb_c1_w)}
  Welch t-test (C1 vs C2) : t={t_c1_c2_w:.3f}  p={p_c1_c2_w:.6f}  d={d_c1_c2_w:.3f}  → {sig(p_c1_c2_w)}

──────────────────────────────────────────────────────────────
 CONTEXT SWITCHES
──────────────────────────────────────────────────────────────
  SB  : {stats_c["SB"][0]:.0f}   ± {stats_c["SB"][1]:.0f} SD
  C1  : {stats_c["C1"][0]:.0f}   ± {stats_c["C1"][1]:.0f} SD   ({pct(stats_c["SB"][0], stats_c["C1"][0]):+.1f}% vs SB)
  C2  : {stats_c["C2"][0]:.0f}   ± {stats_c["C2"][1]:.0f} SD   ({pct(stats_c["SB"][0], stats_c["C2"][0]):+.1f}% vs SB)

  Welch t-test (SB vs C1) : t={t_sb_c1_c:.3f}  p={p_sb_c1_c:.6f}  d={d_sb_c1_c:.3f}  → {sig(p_sb_c1_c)}
  Welch t-test (C1 vs C2) : t={t_c1_c2_c:.3f}  p={p_c1_c2_c:.6f}  d={d_c1_c2_c:.3f}  → {sig(p_c1_c2_c)}

──────────────────────────────────────────────────────────────
 CONCLUSIONS
──────────────────────────────────────────────────────────────
  Tuning 1 — CPU Affinity (SB → C1):
    Hardware-level tuning. Spreading {6} processes across 2 cores
    reduces execution time and context switches by eliminating
    forced time-sharing on a single core.

  Tuning 2 — Real-Time Scheduler (C1 → C2):
    Scheduler-level tuning. Promoting the measured process to
    SCHED_RR (chrt -r 99) prevents involuntary preemption by
    lower-priority sibling processes, reducing context switches.

  Note: Results reflect controlled stress conditions ({6} competing
  processes on constrained cores). Effects may differ at lower load.

──────────────────────────────────────────────────────────────
 PLOTS GENERATED
──────────────────────────────────────────────────────────────
  1_execution_time_bar.png     — Mean + SE bar chart
  2_context_switches_bar.png   — Mean + SE bar chart
  3_execution_time_box.png     — Box / IQR distribution
  4_context_switches_box.png   — Box / IQR distribution
  5_execution_time_kde.png     — KDE density curves
  6_context_switches_kde.png   — KDE density curves
"""

print(report)
REPORT.write_text(report)
print(f"[analyze] Report → {REPORT}")
print(f"[analyze] Plots  → {PLOTS}/")
PYEOF