#!/usr/bin/env python3

import json
import os

DEVICE = input("Enter disk device (e.g., sda, nvme0n1): ").strip()
FEATURE_FILE = input("Enter feature JSON path: ").strip()

with open(FEATURE_FILE) as f:
    features = json.load(f)

commands = []

# -----------------------------------
# Scheduler Selection
# -----------------------------------
if features.get("avg_util", 0) > 70 or features.get("avg_queue", 0) > 1:
    commands.append(f"echo mq-deadline | sudo tee /sys/block/{DEVICE}/queue/scheduler")

# -----------------------------------
# Read-Ahead Logic
# -----------------------------------
if features.get("avg_req_size", 0) > 512:
    # likely sequential
    commands.append(f"sudo blockdev --setra 4096 /dev/{DEVICE}")
else:
    # likely random
    commands.append(f"sudo blockdev --setra 128 /dev/{DEVICE}")

# -----------------------------------
# Dirty Page Tuning
# -----------------------------------
if features.get("avg_iowait", 0) > 10:
    commands.append("sudo sysctl -w vm.dirty_ratio=15")
    commands.append("sudo sysctl -w vm.dirty_background_ratio=5")

# -----------------------------------
# PSI-based aggressive tuning
# -----------------------------------
if features.get("psi_some_avg10", 0) > 0.1:
    commands.append(f"echo none | sudo tee /sys/block/{DEVICE}/queue/scheduler")

# -----------------------------------
# Output Commands
# -----------------------------------
print("\n===== Recommended Tuning Actions =====\n")

for cmd in commands:
    print(cmd)

print("\nNOTE: Review before executing. These modify system behavior.")