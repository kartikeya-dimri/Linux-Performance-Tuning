#!/usr/bin/env python3
"""
mem_avg.py — Average feature JSONs across N iterations and save results.

Usage:
    python3 mem_avg.py <N_iterations> <workload1> [workload2 ...]

Reads:
    logs/<workload>/iter_<i>/before/mem_features_full.json
    logs/<workload>/iter_<i>/after/mem_features_full.json

Writes:
    logs/<workload>/avg_before.json
    logs/<workload>/avg_after.json
    logs/<workload>/summary.txt   ← human-readable comparison table
"""

import os
import sys
import json

N         = int(sys.argv[1])
WORKLOADS = sys.argv[2:]

KEY_METRICS = [
    ("bogo_ops_per_s",       "bogo ops/s",          False),   # higher=better
    ("avg_iowait",           "CPU iowait (%)",       True),    # lower=better
    ("avg_pgfault",          "Page Faults/s",        True),
    ("avg_si_kBps",          "Swap-In (KB/s)",       True),
    ("memory_pressure_score","Pressure Score",       True),
]


def load_json(path):
    with open(path) as f:
        return json.load(f)


def average_jsons(json_list):
    """Return a dict of key → mean across all dicts in json_list."""
    if not json_list:
        return {}
    all_keys = set()
    for d in json_list:
        all_keys.update(d.keys())
    result = {}
    for k in all_keys:
        vals = [d[k] for d in json_list if k in d and d[k] is not None]
        result[k] = sum(vals) / len(vals) if vals else 0.0
    return result


def fmt(v):
    if isinstance(v, float):
        return f"{v:.2f}"
    return str(v)


for WORKLOAD in WORKLOADS:
    print(f"\n{'='*60}")
    print(f"  Workload: {WORKLOAD}  ({N} iterations)")
    print(f"{'='*60}")

    before_jsons = []
    after_jsons  = []
    missing      = []

    for i in range(1, N + 1):
        bp = f"logs/{WORKLOAD}/iter_{i}/before/mem_features_full.json"
        ap = f"logs/{WORKLOAD}/iter_{i}/after/mem_features_full.json"
        if os.path.exists(bp) and os.path.exists(ap):
            before_jsons.append(load_json(bp))
            after_jsons.append(load_json(ap))
            print(f"  [OK] iter {i}")
        else:
            missing.append(i)
            print(f"  [!!] iter {i} missing: {bp if not os.path.exists(bp) else ap}")

    if not before_jsons:
        print(f"  [ERROR] No data found for {WORKLOAD}. Skipping.")
        continue

    if missing:
        print(f"  [WARN] Averaged over {len(before_jsons)} of {N} iterations (missing: {missing})")
    else:
        print(f"  [OK] All {N} iterations loaded.")

    avg_before = average_jsons(before_jsons)
    avg_after  = average_jsons(after_jsons)

    # Save averaged JSONs
    os.makedirs(f"logs/{WORKLOAD}", exist_ok=True)
    with open(f"logs/{WORKLOAD}/avg_before.json", "w") as f:
        json.dump(avg_before, f, indent=4)
    with open(f"logs/{WORKLOAD}/avg_after.json", "w") as f:
        json.dump(avg_after, f, indent=4)

    # Print summary table
    print(f"\n  {'Metric':<30} {'Baseline':>12} {'Tuned':>12} {'Change':>10} {'Better?':>8}")
    print(f"  {'-'*74}")

    summary_lines = []
    for (key, label, lower_better) in KEY_METRICS:
        b = avg_before.get(key, 0)
        a = avg_after.get(key, 0)
        if b != 0:
            pct = (a - b) / abs(b) * 100
            sign = "+" if pct >= 0 else ""
            if lower_better:
                ok = "[OK]" if a < b else "[!!]"
            else:
                ok = "[OK]" if a > b else "[!!]"
            line = f"  {label:<30} {fmt(b):>12} {fmt(a):>12} {sign}{pct:.1f}%{' ':>4} {ok:>8}"
        else:
            line = f"  {label:<30} {fmt(b):>12} {fmt(a):>12} {'N/A':>10} {'':>8}"
        print(line)
        summary_lines.append(line)

    # Save summary text
    summary_path = f"logs/{WORKLOAD}/summary.txt"
    with open(summary_path, "w") as f:
        f.write(f"Workload: {WORKLOAD} | Iterations: {len(before_jsons)}\n")
        f.write(f"{'Metric':<30} {'Baseline':>12} {'Tuned':>12} {'Change':>10} {'Better?':>8}\n")
        f.write("-" * 74 + "\n")
        for line in summary_lines:
            f.write(line.strip() + "\n")

    print(f"\n  Saved: logs/{WORKLOAD}/avg_before.json")
    print(f"  Saved: logs/{WORKLOAD}/avg_after.json")
    print(f"  Saved: {summary_path}")

print("\n[+] Averaging complete.")
