#!/usr/bin/env python3

import os
import re
import json
import pandas as pd

INPUT_DIR = input("Enter baseline directory path: ").strip()

iostat_file = os.path.join(INPUT_DIR, "iostat_clean.log")
vmstat_file = os.path.join(INPUT_DIR, "vmstat_clean.log")
pidstat_file = os.path.join(INPUT_DIR, "pidstat.log")
psi_file = os.path.join(INPUT_DIR, "psi_io.log")


# -----------------------------------------
# Parse iostat
# -----------------------------------------
def parse_iostat(file_path):
    data = []
    headers = []

    with open(file_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

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

    # Filter only main disk
    df = df[df["Device"] == "sda"]

    print("[DEBUG] iostat columns:", list(df.columns))

    return df


# -----------------------------------------
# Parse vmstat
# -----------------------------------------
def parse_vmstat(file_path):
    data = []
    headers = []

    with open(file_path) as f:
        for line in f:
            line = line.strip()

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
# Parse pidstat
# -----------------------------------------
def parse_pidstat(file_path):
    data = []

    with open(file_path) as f:
        for line in f:
            line = line.strip()

            if not line or "UID" in line or "Average" in line:
                continue

            parts = re.split(r"\s+", line)
            if len(parts) < 7:
                continue

            try:
                kb_rd = float(parts[-4])
                kb_wr = float(parts[-3])
                cmd = parts[-1]

                data.append({
                    "command": cmd,
                    "total_io": kb_rd + kb_wr
                })
            except:
                continue

    if not data:
        return {}

    df = pd.DataFrame(data)
    grouped = df.groupby("command").sum().sort_values("total_io", ascending=False)

    return {
        "top_io_process": grouped.index[0],
        "top_io_kB": grouped.iloc[0]["total_io"]
    }


# -----------------------------------------
# Parse PSI
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
def compute_features(iostat_df, vmstat_df, pidstat_data, psi_data):
    features = {}

    # -----------------------------
    # Latency
    # -----------------------------
    if "await" in iostat_df.columns:
        features["avg_await"] = iostat_df["await"].mean()
    elif "r_await" in iostat_df.columns:
        features["avg_await"] = iostat_df["r_await"].mean()
    else:
        features["avg_await"] = 0

    # -----------------------------
    # Queue
    # -----------------------------
    if "aqu-sz" in iostat_df.columns:
        features["avg_queue"] = iostat_df["aqu-sz"].mean()
    elif "avgqu-sz" in iostat_df.columns:
        features["avg_queue"] = iostat_df["avgqu-sz"].mean()
    else:
        features["avg_queue"] = 0

    # -----------------------------
    # Utilization
    # -----------------------------
    features["avg_util"] = iostat_df["%util"].mean()

    # -----------------------------
    # IOPS
    # -----------------------------
    if "r/s" in iostat_df.columns and "w/s" in iostat_df.columns:
        features["avg_iops"] = (iostat_df["r/s"] + iostat_df["w/s"]).mean()
    else:
        features["avg_iops"] = 0

    # -----------------------------
    # Throughput
    # -----------------------------
    if "rkB/s" in iostat_df.columns:
        features["avg_throughput_kBps"] = (
            iostat_df["rkB/s"] + iostat_df["wkB/s"]
        ).mean()
    elif "rMB/s" in iostat_df.columns:
        features["avg_throughput_kBps"] = (
            (iostat_df["rMB/s"] + iostat_df["wMB/s"]) * 1024
        ).mean()
    else:
        features["avg_throughput_kBps"] = 0

    # -----------------------------
    # CPU interaction
    # -----------------------------
    features["avg_iowait"] = vmstat_df["wa"].mean()

    # -----------------------------
    # Merge extras
    # -----------------------------
    features.update(pidstat_data)
    features.update(psi_data)

    # -----------------------------
    # Derived score
    # -----------------------------
    features["disk_pressure_score"] = (
        features["avg_util"] * 0.3 +
        features["avg_queue"] * 0.3 +
        features["avg_iowait"] * 0.2 +
        features.get("psi_some_avg10", 0) * 0.2
    )

    return features


# -----------------------------------------
# Main
# -----------------------------------------
def main():
    iostat_df = parse_iostat(iostat_file)
    vmstat_df = parse_vmstat(vmstat_file)
    pidstat_data = parse_pidstat(pidstat_file)
    psi_data = parse_psi(psi_file)

    features = compute_features(iostat_df, vmstat_df, pidstat_data, psi_data)

    json_path = os.path.join(INPUT_DIR, "disk_features_full.json")

    with open(json_path, "w") as f:
        json.dump(features, f, indent=4)

    print("\n[+] Features extracted:")
    for k, v in features.items():
        print(f"{k}: {round(v,2) if isinstance(v,float) else v}")


if __name__ == "__main__":
    main()