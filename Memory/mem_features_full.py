#!/usr/bin/env python3

import os
import re
import json
import pandas as pd

INPUT_DIR = input("Enter run directory path: ").strip()

vmstat_file      = os.path.join(INPUT_DIR, "vmstat_clean.log")
meminfo_file     = os.path.join(INPUT_DIR, "meminfo.log")
vmstat_proc_file = os.path.join(INPUT_DIR, "vmstat_proc.log")
psi_file         = os.path.join(INPUT_DIR, "psi_mem.log")


# -----------------------------------------
# Parse vmstat (the sysstat output)
# Columns of interest: si (swap in), so (swap out),
#   free, buff, cache, wa (iowait)
# -----------------------------------------
def parse_vmstat(file_path):
    data = []
    headers = []

    with open(file_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # vmstat header starts with 'r '
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

    print("[DEBUG] vmstat columns:", list(df.columns))
    return df


# -----------------------------------------
# Parse /proc/meminfo snapshots
# Returns a DataFrame with one row per snapshot
# Key fields: MemFree, MemAvailable, Cached, Buffers,
#             SwapTotal, SwapFree → SwapUsed = Total - Free
# -----------------------------------------
def parse_meminfo(file_path):
    snapshots = []
    current = {}

    with open(file_path) as f:
        for line in f:
            line = line.strip()

            if line == "---SNAPSHOT---":
                if current:
                    snapshots.append(current)
                current = {}
                continue

            # Skip timestamp lines (contain '-')
            if re.match(r"\d{4}-\d{2}-\d{2}", line):
                continue

            # Parse "Key: value kB"
            m = re.match(r"^(\w+):\s+(\d+)", line)
            if m:
                current[m.group(1)] = int(m.group(2))

    if current:
        snapshots.append(current)

    if not snapshots:
        print("[WARNING] No meminfo snapshots found.")
        return pd.DataFrame()

    df = pd.DataFrame(snapshots)

    # Derive SwapUsed
    if "SwapTotal" in df.columns and "SwapFree" in df.columns:
        df["SwapUsed"] = df["SwapTotal"] - df["SwapFree"]

    # Convert kB to MB for readability
    kb_cols = ["MemFree", "MemAvailable", "Cached", "Buffers",
               "SwapTotal", "SwapFree", "SwapUsed", "MemTotal"]
    for col in kb_cols:
        if col in df.columns:
            df[col + "_MB"] = df[col] / 1024.0

    print("[DEBUG] meminfo columns:", list(df.columns))
    return df


# -----------------------------------------
# Parse /proc/vmstat snapshots
# Computes per-second DELTAS for:
#   pgfault, pgmajfault, pswpin, pswpout
# -----------------------------------------
def parse_proc_vmstat(file_path):
    snapshots = []
    current = {}

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
        print("[WARNING] Not enough /proc/vmstat snapshots for delta computation.")
        return {}

    df = pd.DataFrame(snapshots)

    keys = ["pgfault", "pgmajfault", "pswpin", "pswpout"]
    deltas = {}

    for k in keys:
        if k in df.columns:
            # Compute per-interval deltas (snapshot i+1 - snapshot i)
            d = df[k].diff().dropna()
            deltas[f"avg_{k}"] = d.mean()

    print("[DEBUG] /proc/vmstat deltas computed:", list(deltas.keys()))
    return deltas


# -----------------------------------------
# Parse /proc/pressure/memory (PSI)
# -----------------------------------------
def parse_psi(file_path):
    some_vals = []

    with open(file_path) as f:
        for line in f:
            if "some avg10=" in line:
                match = re.search(r"avg10=(\d+\.\d+)", line)
                if match:
                    some_vals.append(float(match.group(1)))

    return {
        "psi_some_avg10": sum(some_vals) / len(some_vals) if some_vals else 0
    }


# -----------------------------------------
# Feature Computation
# -----------------------------------------
def compute_features(vmstat_df, meminfo_df, proc_vmstat_deltas, psi_data):
    features = {}

    # --- Swap activity from vmstat ---
    if "si" in vmstat_df.columns:
        features["avg_si_kBps"] = vmstat_df["si"].mean()   # swap in KB/s
    else:
        features["avg_si_kBps"] = 0

    if "so" in vmstat_df.columns:
        features["avg_so_kBps"] = vmstat_df["so"].mean()   # swap out KB/s
    else:
        features["avg_so_kBps"] = 0

    # --- Free memory from vmstat ---
    if "free" in vmstat_df.columns:
        # vmstat reports free in KB
        features["avg_free_vmstat_MB"] = vmstat_df["free"].mean() / 1024.0
    else:
        features["avg_free_vmstat_MB"] = 0

    # --- CPU iowait from vmstat ---
    if "wa" in vmstat_df.columns:
        features["avg_iowait"] = vmstat_df["wa"].mean()
    else:
        features["avg_iowait"] = 0

    # --- Memory metrics from /proc/meminfo snapshots ---
    if not meminfo_df.empty:
        if "MemFree_MB" in meminfo_df.columns:
            features["avg_free_mb"] = meminfo_df["MemFree_MB"].mean()
        if "SwapUsed_MB" in meminfo_df.columns:
            features["avg_swap_used_mb"] = meminfo_df["SwapUsed_MB"].mean()
        if "Cached_MB" in meminfo_df.columns and "Buffers_MB" in meminfo_df.columns:
            features["avg_cache_mb"] = (
                meminfo_df["Cached_MB"] + meminfo_df["Buffers_MB"]
            ).mean()
        if "MemAvailable_MB" in meminfo_df.columns:
            features["avg_available_mb"] = meminfo_df["MemAvailable_MB"].mean()

    # --- Page fault + swap deltas from /proc/vmstat ---
    features.update(proc_vmstat_deltas)

    # --- PSI ---
    features.update(psi_data)

    # --- Derived composite memory pressure score ---
    # Weights chosen to mirror disk_pressure_score structure
    swap_pressure = (
        features.get("avg_si_kBps", 0) +
        features.get("avg_so_kBps", 0)
    ) / 100.0   # normalize KB/s to a 0-100 scale roughly

    features["memory_pressure_score"] = (
        min(swap_pressure, 100) * 0.25 +
        min(features.get("avg_pgmajfault", 0) / 10.0, 100) * 0.25 +
        features.get("avg_iowait", 0) * 0.25 +
        features.get("psi_some_avg10", 0) * 0.25
    )

    return features


# -----------------------------------------
# Main
# -----------------------------------------
def main():
    vmstat_df         = parse_vmstat(vmstat_file)
    meminfo_df        = parse_meminfo(meminfo_file)
    proc_vmstat_data  = parse_proc_vmstat(vmstat_proc_file)
    psi_data          = parse_psi(psi_file)

    features = compute_features(vmstat_df, meminfo_df, proc_vmstat_data, psi_data)

    json_path = os.path.join(INPUT_DIR, "mem_features_full.json")

    with open(json_path, "w") as f:
        json.dump(features, f, indent=4)

    print(f"\n[+] Features extracted and saved to {json_path}")
    for k, v in features.items():
        print(f"  {k}: {round(v, 2) if isinstance(v, float) else v}")


if __name__ == "__main__":
    main()
