#!/usr/bin/env python3

import json
import sys

FEATURE_FILE = input("Enter feature JSON path: ").strip()

with open(FEATURE_FILE) as f:
    features = json.load(f)

print("\n===== Memory Tuning Decision =====\n")

commands = []
reasons  = []

# -----------------------------------------
# Read key features
# -----------------------------------------
avg_si       = features.get("avg_si_kBps", 0)
avg_so       = features.get("avg_so_kBps", 0)
pgmajfault   = features.get("avg_pgmajfault", 0)
psi          = features.get("psi_some_avg10", 0)
avg_free_mb  = features.get("avg_free_mb", 9999)
swap_used_mb = features.get("avg_swap_used_mb", 0)

# -----------------------------------------
# Workload detection (analogous to disk's write_ratio / req_size logic)
#
# swap-heavy  → lots of si+so activity     → like "sequential" in disk
# fault-heavy → lots of major page faults  → like "random" in disk
# mixed       → both                       → like "mix" in disk
# -----------------------------------------
swap_activity = avg_si + avg_so

if swap_activity > 20 and pgmajfault > 50:
    workload = "mix"
    reasons.append(f"Both swap ({swap_activity:.1f} KB/s) and major faults ({pgmajfault:.1f}/s) are high")
elif swap_activity > 20:
    workload = "swap-heavy"
    reasons.append(f"High swap activity: si+so = {swap_activity:.1f} KB/s")
elif pgmajfault > 50:
    workload = "fault-heavy"
    reasons.append(f"High major page fault rate: {pgmajfault:.1f}/s")
else:
    workload = "mix"
    reasons.append("Moderate memory pressure — treating as mixed")

print(f"Detected Workload Type: {workload}")
print(f"Reason: {reasons[0]}")

# -----------------------------------------
# vm.swappiness
# Lower = keep anon pages in RAM longer
# All workloads benefit from lower swappiness
# unless the system truly has no RAM pressure
# -----------------------------------------
if avg_free_mb < 200 or swap_used_mb > 512:
    swappiness = 10
    reasons.append(f"Low free RAM ({avg_free_mb:.0f} MB) or high swap use ({swap_used_mb:.0f} MB) → aggressive swappiness reduction")
else:
    swappiness = 30
    reasons.append("Moderate memory pressure → moderate swappiness reduction")

commands.append(f"sudo sysctl -w vm.swappiness={swappiness}")

# -----------------------------------------
# vm.dirty_ratio / vm.dirty_background_ratio
# swap-heavy → allow more buffering to reduce flush-induced eviction
# fault-heavy → more moderate buffering
# -----------------------------------------
if workload == "swap-heavy":
    dirty_ratio = 20
    dirty_bg    = 10
    reasons.append("Swap-heavy → allow larger dirty buffers to reduce flush-triggered eviction")
elif workload == "fault-heavy":
    dirty_ratio = 15
    dirty_bg    = 5
    reasons.append("Fault-heavy → moderate dirty ratio to balance cache residency")
else:  # mix
    dirty_ratio = 20
    dirty_bg    = 10
    reasons.append("Mixed → larger dirty buffers as a safe compromise")

commands.append(f"sudo sysctl -w vm.dirty_ratio={dirty_ratio}")
commands.append(f"sudo sysctl -w vm.dirty_background_ratio={dirty_bg}")

# -----------------------------------------
# Transparent Huge Pages (THP)
# alloc/swap-heavy: 'always' → reduce TLB misses on large anon allocations
# fault-heavy: 'madvise' → avoid compaction overhead for sparse access
# mix: 'madvise' → safe compromise
# -----------------------------------------
if workload == "swap-heavy":
    thp = "always"
    reasons.append("Swap-heavy (anon) workload → THP always reduces TLB pressure")
else:
    thp = "madvise"
    reasons.append("Mixed/fault-heavy → THP madvise avoids compaction overhead")

commands.append(f"echo {thp} | sudo tee /sys/kernel/mm/transparent_hugepage/enabled")

# -----------------------------------------
# Output
# -----------------------------------------
print(f"\nSwappiness    : {swappiness}")
print(f"dirty_ratio   : {dirty_ratio}")
print(f"dirty_bg_ratio: {dirty_bg}")
print(f"THP           : {thp}")

print("\n--- Commands to Apply ---")
for cmd in commands:
    print(cmd)

print("\n--- Reasons ---")
for r in reasons:
    print("-", r)
