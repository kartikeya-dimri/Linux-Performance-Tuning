#!/usr/bin/env python3

import json

DEVICE = input("Enter disk device (e.g., sda, nvme0n1): ").strip()
FEATURE_FILE = input("Enter feature JSON path: ").strip()

with open(FEATURE_FILE) as f:
    features = json.load(f)

print("\n===== Tuning Decision =====\n")

commands = []
reasons = []

queue = features.get("avg_queue", 0)
req_size = features.get("avg_req_size", 0)
write_ratio = features.get("write_ratio", 0)

# Workload detection
if write_ratio > 0.15:
    workload = "mixed"
elif req_size > 128:
    workload = "sequential"
elif req_size < 32:
    workload = "random"
else:
    workload = "mixed"

print(f"Detected Workload: {workload}")

# Scheduler
if queue > 50:
    scheduler = "mq-deadline"
    reasons.append("High queue → scheduling needed")
else:
    scheduler = "none"
    reasons.append("Low queue → reduce overhead")

commands.append(f"echo {scheduler} | sudo tee /sys/block/{DEVICE}/queue/scheduler")

# Read-ahead
if workload == "sequential":
    readahead = 1024
elif workload == "mixed":
    readahead = 512
else:
    readahead = 128

commands.append(f"sudo blockdev --setra {readahead} /dev/{DEVICE}")

print("\nCommands:")
for cmd in commands:
    print(cmd)