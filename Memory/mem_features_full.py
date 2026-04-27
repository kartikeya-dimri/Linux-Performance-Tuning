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
stress_log_file  = os.path.join(INPUT_DIR, "stress_ng.log")


# -----------------------------------------
# Parse vmstat (sysstat tool output)
# Columns of interest:
#   si  = swap in  (KB/s)
#   so  = swap out (KB/s)
#   free, buff, cache
#   wa  = CPU iowait %
# -----------------------------------------
def parse_vmstat(file_path):
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

    print("[DEBUG] vmstat columns:", list(df.columns))
    return df


# -----------------------------------------
# Parse /proc/meminfo snapshots
# -----------------------------------------
def parse_meminfo(file_path):
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
            m = re.match(r"^(\w+):\s+(\d+)", line)
            if m:
                current[m.group(1)] = int(m.group(2))

    if current:
        snapshots.append(current)

    if not snapshots:
        print("[WARNING] No meminfo snapshots found.")
        return pd.DataFrame()

    df = pd.DataFrame(snapshots)

    if "SwapTotal" in df.columns and "SwapFree" in df.columns:
        df["SwapUsed"] = df["SwapTotal"] - df["SwapFree"]

    # Convert kB → MB
    kb_cols = ["MemFree", "MemAvailable", "Cached", "Buffers",
               "SwapTotal", "SwapFree", "SwapUsed", "MemTotal"]
    for col in kb_cols:
        if col in df.columns:
            df[col + "_MB"] = df[col] / 1024.0

    print("[DEBUG] meminfo snapshots:", len(snapshots))
    return df


# -----------------------------------------
# Parse /proc/vmstat snapshots → per-second deltas
# Key counters: pgfault, pgmajfault, pswpin, pswpout
# -----------------------------------------
def parse_proc_vmstat(file_path):
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
        print("[WARNING] Not enough /proc/vmstat snapshots.")
        return {}

    df      = pd.DataFrame(snapshots)
    keys    = ["pgfault", "pgmajfault", "pswpin", "pswpout"]
    deltas  = {}

    for k in keys:
        if k in df.columns:
            d = df[k].diff().dropna()
            d = d[d >= 0]   # drop negative (counter reset)
            deltas[f"avg_{k}"] = d.mean() if len(d) > 0 else 0

    print("[DEBUG] /proc/vmstat deltas:", {k: round(v, 2) for k, v in deltas.items()})
    return deltas


# -----------------------------------------
# Parse /proc/pressure/memory (PSI)
# -----------------------------------------
def parse_psi(file_path):
    some_vals = []
    full_vals = []

    with open(file_path) as f:
        for line in f:
            if "some avg10=" in line:
                m = re.search(r"avg10=(\d+\.\d+)", line)
                if m:
                    some_vals.append(float(m.group(1)))
            if "full avg10=" in line:
                m = re.search(r"avg10=(\d+\.\d+)", line)
                if m:
                    full_vals.append(float(m.group(1)))

    return {
        "psi_some_avg10": sum(some_vals) / len(some_vals) if some_vals else 0,
        "psi_full_avg10": sum(full_vals) / len(full_vals) if full_vals else 0,
    }


# -----------------------------------------
# Parse stress-ng output for bogo ops/s
# Actual format from stress-ng --metrics-brief:
#   stress-ng: metrc: [PID] vm   9859986  92.59  87.39  22.16  106485.88  90000.84
#   columns: stressor | bogo-ops | real-secs | usr-secs | sys-secs | bogo/s(real) | bogo/s(usr+sys)
# We want column 6 = bogo ops/s (real time)
# -----------------------------------------
def parse_stress_ng(file_path):
    if not os.path.exists(file_path):
        print("[WARNING] stress_ng.log not found.")
        return {}

    total_bogo_ops_per_s = 0.0
    found = False

    with open(file_path) as f:
        for line in f:
            # Match the metrc data line: stress-ng: metrc: [PID] <stressor> <7 numbers>
            # We want the 6th number (bogo ops/s real time)
            m = re.search(
                r"stress-ng: metrc:.*?\]\s+\w+\s+"
                r"(\d+)\s+"        # bogo ops total
                r"(\d+\.\d+)\s+"  # real time (secs)
                r"(\d+\.\d+)\s+"  # usr time
                r"(\d+\.\d+)\s+"  # sys time
                r"(\d+\.\d+)\s+"  # bogo ops/s (real time)  ← this one
                r"(\d+\.\d+)",    # bogo ops/s (usr+sys)
                line
            )
            if m:
                bogo_per_s = float(m.group(5))  # real-time bogo ops/s
                total_bogo_ops_per_s += bogo_per_s
                found = True
                print(f"[DEBUG] stress-ng stressor bogo ops/s: {bogo_per_s:.2f}")

    if found:
        print(f"[DEBUG] stress-ng total bogo ops/s: {total_bogo_ops_per_s:.2f}")
        return {"bogo_ops_per_s": total_bogo_ops_per_s}

    print("[WARNING] Could not parse bogo ops/s from stress-ng output.")
    return {}


# -----------------------------------------
# Feature Computation
# -----------------------------------------
def compute_features(vmstat_df, meminfo_df, proc_vmstat_deltas, psi_data, stress_data):
    features = {}

    # --- Swap activity from vmstat (KB/s) ---
    features["avg_si_kBps"] = vmstat_df["si"].mean() if "si" in vmstat_df.columns else 0
    features["avg_so_kBps"] = vmstat_df["so"].mean() if "so" in vmstat_df.columns else 0

    # --- Free RAM from vmstat (KB → MB) ---
    if "free" in vmstat_df.columns:
        features["avg_free_vmstat_MB"] = vmstat_df["free"].mean() / 1024.0
    else:
        features["avg_free_vmstat_MB"] = 0

    # --- CPU iowait ---
    features["avg_iowait"] = vmstat_df["wa"].mean() if "wa" in vmstat_df.columns else 0

    # --- Memory metrics from /proc/meminfo ---
    if not meminfo_df.empty:
        if "MemFree_MB"      in meminfo_df.columns: features["avg_free_mb"]       = meminfo_df["MemFree_MB"].mean()
        if "SwapUsed_MB"     in meminfo_df.columns: features["avg_swap_used_mb"]  = meminfo_df["SwapUsed_MB"].mean()
        if "MemAvailable_MB" in meminfo_df.columns: features["avg_available_mb"]  = meminfo_df["MemAvailable_MB"].mean()
        if "Cached_MB" in meminfo_df.columns and "Buffers_MB" in meminfo_df.columns:
            features["avg_cache_mb"] = (meminfo_df["Cached_MB"] + meminfo_df["Buffers_MB"]).mean()

    # --- Page fault + swap deltas from /proc/vmstat ---
    features.update(proc_vmstat_deltas)

    # --- PSI ---
    features.update(psi_data)

    # --- stress-ng throughput ---
    features.update(stress_data)

    # --- Derived composite memory pressure score ---
    # so_norm (avg_so_kBps) is intentionally EXCLUDED:
    #   With swappiness=10, eviction happens in bursts → higher instantaneous
    #   SO rate even though the system performs BETTER (fewer page faults).
    #   Using SO rate would make a better config appear worse.
    # Weights: iowait (dominant — CPU time lost to swap I/O), pgfault (direct
    # measure of swap-in demand), si_kBps (actual swap reads), PSI when available.
    si_norm      = min(features.get("avg_si_kBps", 0) / 1000.0, 100)
    iowait       = features.get("avg_iowait", 0)
    pgfault_norm = min(features.get("avg_pgfault", 0) / 10000.0, 100)
    psi_full     = features.get("psi_full_avg10", 0)
    psi_some     = features.get("psi_some_avg10", 0)

    features["memory_pressure_score"] = (
        iowait        * 0.50 +
        pgfault_norm  * 0.35 +
        si_norm       * 0.10 +
        psi_full      * 0.03 +
        psi_some      * 0.02
    )

    return features


# -----------------------------------------
# Main
# -----------------------------------------
def main():
    vmstat_df        = parse_vmstat(vmstat_file)
    meminfo_df       = parse_meminfo(meminfo_file)
    proc_vmstat_data = parse_proc_vmstat(vmstat_proc_file)
    psi_data         = parse_psi(psi_file)
    stress_data      = parse_stress_ng(stress_log_file)

    features = compute_features(vmstat_df, meminfo_df, proc_vmstat_data, psi_data, stress_data)

    json_path = os.path.join(INPUT_DIR, "mem_features_full.json")
    with open(json_path, "w") as f:
        json.dump(features, f, indent=4)

    print(f"\n[+] Features extracted and saved to {json_path}")
    print("")
    print(f"  {'Feature':<30} {'Value':>15}")
    print(f"  {'-'*46}")
    for k, v in features.items():
        val = round(v, 3) if isinstance(v, float) else v
        print(f"  {k:<30} {str(val):>15}")


if __name__ == "__main__":
    main()
