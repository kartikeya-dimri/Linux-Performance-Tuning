#!/usr/bin/env python3

import os
import sys
import json
import pandas as pd
import matplotlib.pyplot as plt

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
# Metrics to plot (analogous to disk's avg_await, avg_iops, etc.)
# -----------------------------------------
metrics = {
    "avg_free_mb":      "Avg Free Memory (MB) ↑ better",
    "avg_pgmajfault":   "Avg Major Page Faults/s ↓ better",
    "avg_si_kBps":      "Avg Swap In Rate (KB/s) ↓ better",
    "avg_so_kBps":      "Avg Swap Out Rate (KB/s) ↓ better",
    "psi_some_avg10":   "Memory PSI some avg10 ↓ better",
}

COLORS_BEFORE = "#E05C5C"   # red-ish for bad baseline
COLORS_AFTER  = "#4CAF7D"   # green for tuned


for metric, label in metrics.items():
    if metric not in before.index or metric not in after.index:
        print(f"[SKIP] {metric} not found in features — skipping plot.")
        continue

    b_val = before[metric]
    a_val = after[metric]

    fig, ax = plt.subplots(figsize=(6, 4))
    bars = ax.bar(
        ["Baseline", "Tuned"],
        [b_val, a_val],
        color=[COLORS_BEFORE, COLORS_AFTER],
        edgecolor="black",
        linewidth=0.8,
        width=0.5
    )

    # Annotate bar values
    for bar, val in zip(bars, [b_val, a_val]):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() * 1.02,
            f"{val:.2f}",
            ha="center", va="bottom",
            fontsize=10, fontweight="bold"
        )

    # Compute change %
    if b_val != 0:
        change_pct = ((a_val - b_val) / abs(b_val)) * 100
        sign = "+" if change_pct >= 0 else ""
        ax.set_title(f"{label}\n({sign}{change_pct:.1f}% change)", fontsize=11)
    else:
        ax.set_title(label, fontsize=11)

    ax.set_ylabel(metric)
    ax.set_xlabel("Configuration")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    plt.tight_layout()

    out_path = os.path.join(OUTPUT_DIR, f"{metric}.png")
    plt.savefig(out_path, dpi=120)
    plt.close()
    print(f"[+] Saved: {out_path}")

print(f"\n[+] All plots saved in {OUTPUT_DIR}/")
