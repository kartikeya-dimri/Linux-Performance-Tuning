#!/usr/bin/env python3

import os
import sys
import pandas as pd
import numpy as np
import scipy.stats as stats
import json
import re

def parse_iostat(file_path):
    data = []
    headers = []
    with open(file_path) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            if line.startswith("Device"):
                headers = re.split(r"\s+", line)
                continue
            if headers:
                values = re.split(r"\s+", line)
                if len(values) == len(headers):
                    data.append(dict(zip(headers, values)))
    df = pd.DataFrame(data)
    for col in df.columns:
        if col != "Device":
            df[col] = pd.to_numeric(df[col], errors="coerce")
    if "Device" in df.columns:
        df = df[df["Device"] == "sda"]
    return df

def intra_run_stats(before_dir, after_dir):
    print(f"\n{'='*90}")
    print(f" INTRA-RUN STATISTICAL ANALYSIS (Mann-Whitney U on Time-Series Data)")
    print(f" Comparing: {before_dir} vs {after_dir}")
    print(f"{'='*90}")
    
    before_io = os.path.join(before_dir, "iostat_clean.log")
    after_io = os.path.join(after_dir, "iostat_clean.log")
    
    if not os.path.exists(before_io) or not os.path.exists(after_io):
        print(f"[ERROR] Could not find iostat_clean.log in {before_dir} or {after_dir}")
        return
        
    df_before = parse_iostat(before_io)
    df_after = parse_iostat(after_io)
    
    metrics = {
        "r_await": "Read Latency (ms)",
        "w_await": "Write Latency (ms)",
        "aqu-sz": "Queue Depth",
        "%util": "Disk Util (%)"
    }
    
    if "r/s" in df_before.columns and "w/s" in df_before.columns:
        df_before["iops"] = df_before["r/s"] + df_before["w/s"]
        df_after["iops"] = df_after["r/s"] + df_after["w/s"]
        metrics["iops"] = "Total IOPS"
        
    if "rMB/s" in df_before.columns and "wMB/s" in df_before.columns:
        df_before["tput"] = df_before["rMB/s"] + df_before["wMB/s"]
        df_after["tput"] = df_after["rMB/s"] + df_after["wMB/s"]
        metrics["tput"] = "Throughput (MB/s)"
    
    print(f"{'Metric':<20} | {'Before (Median)':<15} | {'After (Median)':<15} | {'P-Value':<10} | {'Significant?':<12}")
    print("-" * 85)
    
    for col, name in metrics.items():
        if col in df_before.columns and col in df_after.columns:
            b_data = df_before[col].dropna()
            a_data = df_after[col].dropna()
            
            if len(b_data) == 0 or len(a_data) == 0:
                continue
                
            # Mann-Whitney U test (non-parametric, good for latency distributions)
            stat, p_val = stats.mannwhitneyu(b_data, a_data, alternative='two-sided')
            
            b_med = b_data.median()
            a_med = a_data.median()
            sig = "Yes (p<0.05)" if p_val < 0.05 else "No"
            
            print(f"{name:<20} | {b_med:<15.2f} | {a_med:<15.2f} | {p_val:<10.2e} | {sig:<12}")
            
    print(f"{'='*90}\n")

def inter_run_stats(iterations):
    print(f"\n{'='*95}")
    print(f" INTER-RUN STATISTICAL ANALYSIS (Welch's T-Test)")
    print(f" Iterations: {iterations}")
    print(f"{'='*95}")
    
    features_before = []
    features_after = []
    
    for i in range(1, iterations + 1):
        b_file = f"run_before_{i}/disk_features_full.json"
        a_file = f"run_after_{i}/disk_features_full.json"
        
        if os.path.exists(b_file) and os.path.exists(a_file):
            with open(b_file) as f:
                features_before.append(json.load(f))
            with open(a_file) as f:
                features_after.append(json.load(f))
        else:
            print(f"Warning: Missing data for iteration {i}")
            
    if len(features_before) < 2:
        print("[ERROR] Need at least 2 complete iterations to perform inter-run stats.")
        return
        
    df_b = pd.DataFrame(features_before)
    df_a = pd.DataFrame(features_after)
    
    metrics = ["avg_await", "avg_iops", "avg_throughput_kBps", "psi_some_avg10", "avg_util"]
    
    print(f"{'Metric':<20} | {'Before (Mean ± SD)':<22} | {'After (Mean ± SD)':<22} | {'P-Value':<10} | {'Significant?':<12}")
    print("-" * 95)
    
    for m in metrics:
        if m in df_b.columns and m in df_a.columns:
            b_data = df_b[m].dropna()
            a_data = df_a[m].dropna()
            
            if len(b_data) < 2 or len(a_data) < 2:
                continue
                
            # Welch's t-test (handles unequal variances)
            stat, p_val = stats.ttest_ind(b_data, a_data, equal_var=False)
            
            b_mean, b_sd = b_data.mean(), b_data.std()
            a_mean, a_sd = a_data.mean(), a_data.std()
            sig = "Yes (p<0.05)" if p_val < 0.05 else "No"
            
            b_str = f"{b_mean:.1f} ± {b_sd:.1f}"
            a_str = f"{a_mean:.1f} ± {a_sd:.1f}"
            
            print(f"{m:<20} | {b_str:<22} | {a_str:<22} | {p_val:<10.2e} | {sig:<12}")
            
    print(f"{'='*95}\n")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 disk_stats.py intra <before_dir> <after_dir>")
        print("  python3 disk_stats.py inter <num_iterations>")
        sys.exit(1)
        
    mode = sys.argv[1]
    if mode == "intra" and len(sys.argv) == 4:
        intra_run_stats(sys.argv[2], sys.argv[3])
    elif mode == "inter" and len(sys.argv) == 3:
        inter_run_stats(int(sys.argv[2]))
    else:
        print("Invalid arguments.")
