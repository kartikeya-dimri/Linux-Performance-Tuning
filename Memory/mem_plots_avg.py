#!/usr/bin/env python3
"""
mem_plots_avg.py — Generate comparison bar plots from averaged feature JSONs.

Reads averaged before/after JSONs produced by mem_avg.py.
Input via stdin (same as mem_plots.py):
    <before_json_path>
    <after_json_path>
    <workload_label>

Example:
    echo -e "logs/alloc/avg_before.json\nlogs/alloc/avg_after.json\nalloc_final" | python3 mem_plots_avg.py
"""

import os
import sys
import json
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

lines        = sys.stdin.read().strip().split("\n")
before_path  = lines[0].strip()
after_path   = lines[1].strip()
workload     = lines[2].strip()

OUTPUT_DIR = f"comparison_plots_{workload}"
os.makedirs(OUTPUT_DIR, exist_ok=True)

with open(before_path) as f:
    before = json.load(f)
with open(after_path) as f:
    after = json.load(f)

metrics = [
    ("bogo_ops_per_s",        "stress-ng Throughput (bogo ops/s)",  False),
    ("avg_iowait",            "CPU iowait - waiting on swap (%)",   True),
    ("avg_pgfault",           "Page Faults per Second",             True),
    ("avg_si_kBps",           "Swap-In Rate (KB/s)",                True),
    ("memory_pressure_score", "Memory Pressure Score (composite)",  True),
]

COLOR_BEFORE = "#C0392B"
COLOR_AFTER  = "#27AE60"


def make_bar(metric, label, lower_is_better):
    b_val = float(before.get(metric, 0))
    a_val = float(after.get(metric, 0))

    if b_val == 0 and a_val == 0:
        print(f"[SKIP] {metric}: both values are 0.")
        return

    if lower_is_better:
        improved = a_val < b_val
    else:
        improved = a_val > b_val

    fig, ax = plt.subplots(figsize=(6, 4.5))
    bars = ax.bar(
        ["Baseline\n(Bad Config)", "Tuned\n(Optimized)"],
        [b_val, a_val],
        color=[COLOR_BEFORE, COLOR_AFTER],
        edgecolor="black",
        linewidth=0.8,
        width=0.5
    )
    for bar, val in zip(bars, [b_val, a_val]):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() * 1.03,
            f"{val:.1f}",
            ha="center", va="bottom",
            fontsize=11, fontweight="bold"
        )

    if b_val != 0:
        change_pct = ((a_val - b_val) / abs(b_val)) * 100
        sign      = "+" if change_pct >= 0 else ""
        direction = "[OK]" if improved else "[!!]"
        title = f"{label}\n{direction}  {sign}{change_pct:.1f}% change  (avg {len([1])} iters)"
    else:
        title = label

    ax.set_title(title, fontsize=10, pad=10)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    before_patch = mpatches.Patch(color=COLOR_BEFORE, label="Baseline (bad config)")
    after_patch  = mpatches.Patch(color=COLOR_AFTER,  label="Tuned (optimized)")
    ax.legend(handles=[before_patch, after_patch], loc="upper right", fontsize=8)

    plt.tight_layout()
    out_path = os.path.join(OUTPUT_DIR, f"{metric}.png")
    plt.savefig(out_path, dpi=130)
    plt.close()
    print(f"[+] {out_path}  ({b_val:.1f} -> {a_val:.1f})")


for (metric, label, lower_is_better) in metrics:
    make_bar(metric, label, lower_is_better)

print(f"[+] All averaged plots saved to {OUTPUT_DIR}/")
