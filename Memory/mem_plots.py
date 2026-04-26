#!/usr/bin/env python3

import os
import json
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

before_dir = input("Enter BEFORE directory path: ").strip()
after_dir  = input("Enter AFTER directory path: ").strip()
workload   = input("Enter workload name (alloc/cache/mix): ").strip()

OUTPUT_DIR = f"comparison_plots_{workload}"
os.makedirs(OUTPUT_DIR, exist_ok=True)


def load_features(path):
    return pd.read_json(
        os.path.join(path, "mem_features_full.json"),
        typ="series"
    )


before = load_features(before_dir)
after  = load_features(after_dir)

# -----------------------------------------
# Metrics: (feature_key, label, lower_is_better)
# -----------------------------------------
metrics = [
    ("bogo_ops_per_s",    "stress-ng Throughput (bogo ops/s)",  False),   # higher = better ← STAR METRIC
    ("avg_iowait",        "CPU iowait — waiting on swap (%)",   True),    # lower = better
    ("avg_pgfault",       "Page Faults per Second",             True),    # lower = better
    ("avg_so_kBps",       "Swap-Out Rate (KB/s)",               True),    # lower = better
    ("avg_swap_used_mb",  "Avg Swap Used (MB)",                 True),    # lower = better
    ("avg_free_mb",       "Avg Free Memory (MB)",               False),   # higher = better
    ("avg_si_kBps",       "Swap-In Rate (KB/s)",                True),    # lower = better
    ("memory_pressure_score", "Memory Pressure Score",          True),    # lower = better
]

COLOR_BEFORE = "#C0392B"   # deep red — bad baseline
COLOR_AFTER  = "#27AE60"   # deep green — tuned


def make_bar(metric, label, lower_is_better):
    if metric not in before.index or metric not in after.index:
        print(f"[SKIP] {metric} not in features.")
        return

    b_val = float(before[metric])
    a_val = float(after[metric])

    if b_val == 0 and a_val == 0:
        print(f"[SKIP] {metric}: both values are 0.")
        return

    # Determine if improvement happened
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

    # Value labels on bars
    for bar, val in zip(bars, [b_val, a_val]):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() * 1.03,
            f"{val:.1f}",
            ha="center", va="bottom",
            fontsize=11, fontweight="bold"
        )

    # Change % in title
    if b_val != 0:
        change_pct = ((a_val - b_val) / abs(b_val)) * 100
        sign = "+" if change_pct >= 0 else ""
        direction = "✅" if improved else "⚠️"
        title = f"{label}\n{direction}  {sign}{change_pct:.1f}% change"
    else:
        title = label

    ax.set_title(title, fontsize=11, pad=10)
    ax.set_ylabel(label.split("(")[-1].replace(")", "") if "(" in label else label)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    # Legend
    before_patch = mpatches.Patch(color=COLOR_BEFORE, label="Baseline (bad config)")
    after_patch  = mpatches.Patch(color=COLOR_AFTER,  label="Tuned (optimized)")
    ax.legend(handles=[before_patch, after_patch], loc="upper right", fontsize=8)

    plt.tight_layout()
    out_path = os.path.join(OUTPUT_DIR, f"{metric}.png")
    plt.savefig(out_path, dpi=130)
    plt.close()
    print(f"[+] Saved: {out_path}  ({b_val:.1f} → {a_val:.1f})")


for (metric, label, lower_is_better) in metrics:
    make_bar(metric, label, lower_is_better)

print(f"\n[+] All plots saved in {OUTPUT_DIR}/")
