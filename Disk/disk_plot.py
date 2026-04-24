#!/usr/bin/env python3

import os
import re
import pandas as pd
import matplotlib.pyplot as plt

# -------------------------------
# CONFIG
# -------------------------------
BEFORE_DIR = input("Enter BEFORE directory path: ").strip()
AFTER_DIR = input("Enter AFTER directory path: ").strip()
OUTPUT_DIR = "comparison_plots"

os.makedirs(OUTPUT_DIR, exist_ok=True)

# -------------------------------
# PARSERS
# -------------------------------
def parse_iostat(file):
    data = []
    headers = []

    with open(file) as f:
        for line in f:
            line = line.strip()

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


def parse_vmstat(file):
    data = []
    headers = []

    with open(file) as f:
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


# -------------------------------
# LOAD DATA
# -------------------------------
before_iostat = parse_iostat(os.path.join(BEFORE_DIR, "iostat_clean.log"))
after_iostat = parse_iostat(os.path.join(AFTER_DIR, "iostat_clean.log"))

before_vmstat = parse_vmstat(os.path.join(BEFORE_DIR, "vmstat_clean.log"))
after_vmstat = parse_vmstat(os.path.join(AFTER_DIR, "vmstat_clean.log"))

# Aggregate across devices
before_iostat = before_iostat.groupby(before_iostat.index).mean()
after_iostat = after_iostat.groupby(after_iostat.index).mean()

# -------------------------------
# PLOTTING FUNCTION
# -------------------------------
def plot_metric(before, after, column, title, ylabel, filename):
    plt.figure()

    if column in before:
        plt.plot(before[column], label="Before")

    if column in after:
        plt.plot(after[column], label="After")

    plt.title(title)
    plt.xlabel("Time")
    plt.ylabel(ylabel)
    plt.legend()

    plt.savefig(os.path.join(OUTPUT_DIR, filename))
    plt.close()


# -------------------------------
# GENERATE PLOTS
# -------------------------------

# 1. Disk Utilization
plot_metric(
    before_iostat, after_iostat,
    "%util",
    "Disk Utilization Comparison",
    "%util",
    "utilization.png"
)

# 2. Latency
plot_metric(
    before_iostat, after_iostat,
    "await",
    "Disk Latency (await)",
    "ms",
    "latency.png"
)

# 3. Read vs Write Latency
plot_metric(
    before_iostat, after_iostat,
    "r_await",
    "Read Latency",
    "ms",
    "read_latency.png"
)

plot_metric(
    before_iostat, after_iostat,
    "w_await",
    "Write Latency",
    "ms",
    "write_latency.png"
)

# 4. Queue Depth
plot_metric(
    before_iostat, after_iostat,
    "aqu-sz",
    "Queue Depth",
    "queue size",
    "queue.png"
)

# 5. IOPS
if "r/s" in before_iostat and "w/s" in before_iostat:
    before_iostat["iops"] = before_iostat["r/s"] + before_iostat["w/s"]
    after_iostat["iops"] = after_iostat["r/s"] + after_iostat["w/s"]

    plot_metric(
        before_iostat, after_iostat,
        "iops",
        "IOPS Comparison",
        "IOPS",
        "iops.png"
    )

# 6. Throughput
if "rkB/s" in before_iostat and "wkB/s" in before_iostat:
    before_iostat["throughput"] = before_iostat["rkB/s"] + before_iostat["wkB/s"]
    after_iostat["throughput"] = after_iostat["rkB/s"] + after_iostat["wkB/s"]

    plot_metric(
        before_iostat, after_iostat,
        "throughput",
        "Throughput Comparison",
        "kB/s",
        "throughput.png"
    )

# 7. IOWait
plot_metric(
    before_vmstat, after_vmstat,
    "wa",
    "CPU IOWait Comparison",
    "%",
    "iowait.png"
)

print("\nPlots saved in:", OUTPUT_DIR)