#!/usr/bin/env python3

import os
import re
import json
import pandas as pd

INPUT_DIR = input("Enter baseline directory path: ").strip()

# Files
iostat_file = os.path.join(INPUT_DIR, "iostat_clean.log")
vmstat_file = os.path.join(INPUT_DIR, "vmstat_clean.log")
pidstat_file = os.path.join(INPUT_DIR, "pidstat.log")
psi_file = os.path.join(INPUT_DIR, "psi_io.log")


# -------------------------------------------------
# Parse iostat
# -------------------------------------------------
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

    return df


# -------------------------------------------------
# Parse vmstat
# -------------------------------------------------
def parse_vmstat(file_path):
    data = []
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


# -------------------------------------------------
# Parse pidstat (top disk consumers)
# -------------------------------------------------
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
                command = parts[-1]

                data.append({
                    "command": command,
                    "kb_rd": kb_rd,
                    "kb_wr": kb_wr,
                    "total_io": kb_rd + kb_wr
                })
            except:
                continue

    df = pd.DataFrame(data)

    if df.empty:
        return {}

    grouped = df.groupby("command").sum().sort_values("total_io", ascending=False)

    top_process = grouped.index[0]
    top_io = grouped.iloc[0]["total_io"]

    return {
        "top_io_process": top_process,
        "top_io_kB": top_io,
        "total_io_kB": grouped["total_io"].sum()
    }


# -------------------------------------------------
# Parse PSI (I/O pressure)
# -------------------------------------------------
def parse_psi(file_path):
    some_vals = []
    full_vals = []

    with open(file_path) as f:
        for line in f:
            if "some avg10=" in line:
                match = re.search(r"avg10=(\d+\.\d+)", line)
                if match:
                    some_vals.append(float(match.group(1)))

            if "full avg10=" in line:
                match = re.search(r"avg10=(\d+\.\d+)", line)
                if match:
                    full_vals.append(float(match.group(1)))

    return {
        "psi_some_avg10": sum(some_vals) / len(some_vals) if some_vals else 0,
        "psi_full_avg10": sum(full_vals) / len(full_vals) if full_vals else 0
    }


# -------------------------------------------------
# Feature Computation
# -------------------------------------------------
def compute_features(iostat_df, vmstat_df, pidstat_data, psi_data):
    features = {}

    disk_df = iostat_df.copy()
    disk_df = disk_df[~disk_df["Device"].str.contains("loop", na=False)]

    # ---- Disk Core ----
    features["avg_util"] = disk_df["%util"].mean()
    features["max_util"] = disk_df["%util"].max()

    features["avg_await"] = disk_df["await"].mean()

    if "r_await" in disk_df.columns:
        features["avg_r_await"] = disk_df["r_await"].mean()
    if "w_await" in disk_df.columns:
        features["avg_w_await"] = disk_df["w_await"].mean()

    if "aqu-sz" in disk_df.columns:
        features["avg_queue"] = disk_df["aqu-sz"].mean()

    if "r/s" in disk_df.columns and "w/s" in disk_df.columns:
        features["avg_iops"] = (disk_df["r/s"] + disk_df["w/s"]).mean()

    if "rkB/s" in disk_df.columns and "wkB/s" in disk_df.columns:
        features["avg_throughput_kBps"] = (disk_df["rkB/s"] + disk_df["wkB/s"]).mean()

    if "rareq-sz" in disk_df.columns and "wareq-sz" in disk_df.columns:
        features["avg_req_size"] = (
            disk_df["rareq-sz"] + disk_df["wareq-sz"]
        ).mean() / 2

    # ---- CPU Interaction ----
    features["avg_iowait"] = vmstat_df["wa"].mean()
    features["max_iowait"] = vmstat_df["wa"].max()

    # ---- PSI ----
    features.update(psi_data)

    # ---- Process Attribution ----
    features.update(pidstat_data)

    # ---- Derived Indicators ----
    features["disk_pressure_score"] = (
        features.get("avg_util", 0) * 0.3 +
        features.get("avg_queue", 0) * 0.2 +
        features.get("avg_iowait", 0) * 0.2 +
        features.get("psi_some_avg10", 0) * 0.3
    )

    features["latency_severity"] = features.get("avg_await", 0)
    features["queue_severity"] = features.get("avg_queue", 0)

    return features


# -------------------------------------------------
# Main
# -------------------------------------------------
def main():
    print("[+] Parsing logs...")

    iostat_df = parse_iostat(iostat_file)
    vmstat_df = parse_vmstat(vmstat_file)
    pidstat_data = parse_pidstat(pidstat_file)
    psi_data = parse_psi(psi_file)

    print("[+] Computing features...")
    features = compute_features(iostat_df, vmstat_df, pidstat_data, psi_data)

    # Save outputs
    json_path = os.path.join(INPUT_DIR, "disk_features_full.json")
    csv_path = os.path.join(INPUT_DIR, "disk_features_full.csv")

    with open(json_path, "w") as f:
        json.dump(features, f, indent=4)

    pd.DataFrame([features]).to_csv(csv_path, index=False)

    print("[+] Done.")
    print(f"[+] JSON: {json_path}")
    print(f"[+] CSV : {csv_path}")

    print("\n--- Feature Summary ---")
    for k, v in features.items():
        print(f"{k}: {round(v,2) if isinstance(v,float) else v}")


if __name__ == "__main__":
    main()