#!/usr/bin/env python3

import os
import sys
import re
import json
import pandas as pd
import numpy as np
import scipy.stats as stats


# -----------------------------------------
# Parse vmstat_clean.log for time-series data
# -----------------------------------------
def parse_vmstat_timeseries(file_path):
    data    = []
    headers = []

    with open(file_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("r "):
                headers = re.split(r"\s+", line)
                continue
            if headers:
                values = re.split(r"\s+", line)
                if len(values) == len(headers):
                    data.append(dict(zip(headers, values)))

    df = pd.DataFrame(data)
    for col in df.columns:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    return df


# -----------------------------------------
# Parse /proc/vmstat snapshots for delta time-series
# -----------------------------------------
def parse_proc_vmstat_timeseries(file_path):
    snapshots = []
    current   = {}

    with open(file_path) as f:
        for line in f:
            line = line.strip()
            if line == "---SNAPSHOT---":
                if current:
                    snapshots.append(current)
                current = {}
                continue
            if re.match(r"\d{4}-\d{2}-\d{2}", line):
                continue
            m = re.match(r"^(\w+)\s+(\d+)", line)
            if m:
                current[m.group(1)] = int(m.group(2))

    if current:
        snapshots.append(current)

    if len(snapshots) < 2:
        return pd.DataFrame()

    df = pd.DataFrame(snapshots)
    keys = ["pgfault", "pgmajfault", "pswpin", "pswpout"]
    result = {}
    for k in keys:
        if k in df.columns:
            result[k] = df[k].diff().dropna()

    return pd.DataFrame(result)


# -----------------------------------------
# INTRA-RUN: Mann-Whitney U on time-series
# (same approach as disk_stats.py intra_run_stats)
# -----------------------------------------
def intra_run_stats(before_dir, after_dir):
    print(f"\n{'='*90}")
    print(f" INTRA-RUN STATISTICAL ANALYSIS (Mann-Whitney U on Time-Series Data)")
    print(f" Comparing: {before_dir} vs {after_dir}")
    print(f"{'='*90}")

    before_vmstat = os.path.join(before_dir, "vmstat_clean.log")
    after_vmstat  = os.path.join(after_dir,  "vmstat_clean.log")
    before_pvmstat = os.path.join(before_dir, "vmstat_proc.log")
    after_pvmstat  = os.path.join(after_dir,  "vmstat_proc.log")

    if not os.path.exists(before_vmstat) or not os.path.exists(after_vmstat):
        print(f"[ERROR] Could not find vmstat_clean.log in {before_dir} or {after_dir}")
        return

    df_b_vm = parse_vmstat_timeseries(before_vmstat)
    df_a_vm = parse_vmstat_timeseries(after_vmstat)
    df_b_pv = parse_proc_vmstat_timeseries(before_pvmstat)
    df_a_pv = parse_proc_vmstat_timeseries(after_pvmstat)

    # Combine into one unified before/after dict
    # vmstat columns: si, so, free, wa
    # proc/vmstat deltas: pgmajfault, pswpin, pswpout
    vmstat_metrics = {
        "si":  "Swap In (KB/s)",
        "so":  "Swap Out (KB/s)",
        "free": "Free Memory (KB)",
        "wa":  "CPU iowait (%)",
    }
    proc_metrics = {
        "pgmajfault": "Major Page Faults/s",
        "pswpin":     "Pages Swapped In/s",
        "pswpout":    "Pages Swapped Out/s",
    }

    print(f"\n{'Metric':<25} | {'Before (Median)':<15} | {'After (Median)':<15} | {'P-Value':<10} | {'Significant?':<12}")
    print("-" * 85)

    # vmstat metrics
    for col, name in vmstat_metrics.items():
        if col not in df_b_vm.columns or col not in df_a_vm.columns:
            continue
        b_data = df_b_vm[col].dropna()
        a_data = df_a_vm[col].dropna()
        if len(b_data) == 0 or len(a_data) == 0:
            continue
        stat, p_val = stats.mannwhitneyu(b_data, a_data, alternative="two-sided")
        b_med = b_data.median()
        a_med = a_data.median()
        sig   = "Yes (p<0.05)" if p_val < 0.05 else "No"
        print(f"{name:<25} | {b_med:<15.2f} | {a_med:<15.2f} | {p_val:<10.2e} | {sig:<12}")

    # proc/vmstat delta metrics
    if not df_b_pv.empty and not df_a_pv.empty:
        for col, name in proc_metrics.items():
            if col not in df_b_pv.columns or col not in df_a_pv.columns:
                continue
            b_data = df_b_pv[col].dropna()
            a_data = df_a_pv[col].dropna()
            if len(b_data) == 0 or len(a_data) == 0:
                continue
            stat, p_val = stats.mannwhitneyu(b_data, a_data, alternative="two-sided")
            b_med = b_data.median()
            a_med = a_data.median()
            sig   = "Yes (p<0.05)" if p_val < 0.05 else "No"
            print(f"{name:<25} | {b_med:<15.2f} | {a_med:<15.2f} | {p_val:<10.2e} | {sig:<12}")

    print(f"{'='*90}\n")


# -----------------------------------------
# INTER-RUN: Welch's T-Test across N iterations
# -----------------------------------------
def inter_run_stats(iterations):
    print(f"\n{'='*95}")
    print(f" INTER-RUN STATISTICAL ANALYSIS (Welch's T-Test)")
    print(f" Iterations: {iterations}")
    print(f"{'='*95}")

    features_before = []
    features_after  = []

    for i in range(1, iterations + 1):
        b_file = f"run_before_{i}/mem_features_full.json"
        a_file = f"run_after_{i}/mem_features_full.json"

        if os.path.exists(b_file) and os.path.exists(a_file):
            with open(b_file) as f:
                features_before.append(json.load(f))
            with open(a_file) as f:
                features_after.append(json.load(f))
        else:
            print(f"[WARNING] Missing data for iteration {i}")

    if len(features_before) < 2:
        print("[ERROR] Need at least 2 complete iterations for inter-run stats.")
        return

    df_b = pd.DataFrame(features_before)
    df_a = pd.DataFrame(features_after)

    metrics = [
        "avg_free_mb",
        "avg_swap_used_mb",
        "avg_pgmajfault",
        "avg_si_kBps",
        "avg_so_kBps",
        "psi_some_avg10",
        "memory_pressure_score",
    ]

    print(f"\n{'Metric':<25} | {'Before (Mean ± SD)':<22} | {'After (Mean ± SD)':<22} | {'P-Value':<10} | {'Significant?':<12}")
    print("-" * 100)

    for m in metrics:
        if m not in df_b.columns or m not in df_a.columns:
            continue
        b_data = df_b[m].dropna()
        a_data = df_a[m].dropna()
        if len(b_data) < 2 or len(a_data) < 2:
            continue

        stat, p_val = stats.ttest_ind(b_data, a_data, equal_var=False)
        b_mean, b_sd = b_data.mean(), b_data.std()
        a_mean, a_sd = a_data.mean(), a_data.std()
        sig = "Yes (p<0.05)" if p_val < 0.05 else "No"

        b_str = f"{b_mean:.1f} ± {b_sd:.1f}"
        a_str = f"{a_mean:.1f} ± {a_sd:.1f}"

        print(f"{m:<25} | {b_str:<22} | {a_str:<22} | {p_val:<10.2e} | {sig:<12}")

    print(f"{'='*100}\n")


# -----------------------------------------
# Entry Point
# -----------------------------------------
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 mem_stats.py intra <before_dir> <after_dir>")
        print("  python3 mem_stats.py inter <num_iterations>")
        sys.exit(1)

    mode = sys.argv[1]

    if mode == "intra" and len(sys.argv) == 4:
        intra_run_stats(sys.argv[2], sys.argv[3])
    elif mode == "inter" and len(sys.argv) == 3:
        inter_run_stats(int(sys.argv[2]))
    else:
        print("Invalid arguments.")
        print("  python3 mem_stats.py intra <before_dir> <after_dir>")
        print("  python3 mem_stats.py inter <num_iterations>")
