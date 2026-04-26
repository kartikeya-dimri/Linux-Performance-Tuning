#!/usr/bin/env python3

import json
import sys
import subprocess

# -----------------------------------------
# Usage:
#   python3 mem_tuning.py --apply path/to/mem_features_full.json
#   echo "path/to/mem_features_full.json" | python3 mem_tuning.py
# -----------------------------------------

APPLY_MODE = "--apply" in sys.argv

if APPLY_MODE:
    FEATURE_FILE = sys.argv[-1]
else:
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
psi_some     = features.get("psi_some_avg10", 0)
psi_full     = features.get("psi_full_avg10", 0)
avg_free_mb  = features.get("avg_free_mb", 9999)
swap_used_mb = features.get("avg_swap_used_mb", 0)
bogo_ops     = features.get("bogo_ops_per_s", 0)

# -----------------------------------------
# Workload detection
# -----------------------------------------
swap_activity = avg_si + avg_so

if swap_activity > 100 and pgmajfault > 50:
    workload = "mix"
    reasons.append(f"Both swap ({swap_activity:.1f} KB/s) and major faults ({pgmajfault:.1f}/s) are high")
elif swap_activity > 100:
    workload = "swap-heavy"
    reasons.append(f"High swap activity: si+so = {swap_activity:.1f} KB/s")
elif pgmajfault > 50:
    workload = "fault-heavy"
    reasons.append(f"High major page fault rate: {pgmajfault:.1f}/s")
elif psi_some > 5 or psi_full > 1:
    workload = "pressure-heavy"
    reasons.append(f"High PSI: some={psi_some:.2f}%, full={psi_full:.2f}%")
else:
    workload = "mix"
    reasons.append("Moderate/mixed memory pressure")

print(f"Detected Workload Type : {workload}")
print(f"Baseline bogo ops/s    : {bogo_ops:.2f}" if bogo_ops else "")
print(f"Reason                 : {reasons[0]}")

# =============================================
# TUNING DECISIONS
# =============================================

# -----------------------------------------
# 1. vm.swappiness
# Lower = keep anon pages in RAM longer
# Under genuine pressure this is critical
# -----------------------------------------
swappiness = 10
reasons.append(f"swappiness=10: minimize anonymous page eviction (was 200 — 20× reduction)")
commands.append(f"sudo sysctl -w vm.swappiness={swappiness}")

# -----------------------------------------
# 2. vm.vfs_cache_pressure
# 100 = default (equal treatment of page cache vs anon)
# 50  = kernel prefers to keep page cache over anon (good for cache workloads)
# -----------------------------------------
if workload in ("fault-heavy", "mix", "pressure-heavy"):
    cache_pressure = 50
    reasons.append("vfs_cache_pressure=50: preserve page cache residency (was 500 — 10× reduction)")
else:
    cache_pressure = 100
    reasons.append("vfs_cache_pressure=100: balanced eviction policy")

commands.append(f"sudo sysctl -w vm.vfs_cache_pressure={cache_pressure}")

# -----------------------------------------
# 3. vm.dirty_ratio / vm.dirty_background_ratio
# -----------------------------------------
dirty_ratio = 20
dirty_bg    = 10
reasons.append("dirty_ratio=20/10: allow write buffering to reduce flush-triggered eviction (was 5/2)")
commands.append(f"sudo sysctl -w vm.dirty_ratio={dirty_ratio}")
commands.append(f"sudo sysctl -w vm.dirty_background_ratio={dirty_bg}")

# -----------------------------------------
# 4. vm.min_free_kbytes
# Higher = kernel starts reclaim earlier → smoother, no sudden stalls
# 262144 KB = 256 MB reserve (~3.1% of 8 GB)
# -----------------------------------------
min_free = 262144
reasons.append("min_free_kbytes=262144: early reclaim trigger prevents sudden stalls (was 16384 — 16× increase)")
commands.append(f"sudo sysctl -w vm.min_free_kbytes={min_free}")

# -----------------------------------------
# 5. Transparent Huge Pages (THP)
# -----------------------------------------
if workload in ("swap-heavy", "mix"):
    thp = "always"
    reasons.append("THP=always: 2MB pages reduce TLB pressure for bulk anon allocations (was never)")
else:
    thp = "madvise"
    reasons.append("THP=madvise: selective huge pages for balanced workload (was never)")

commands.append(f"echo {thp} | sudo tee /sys/kernel/mm/transparent_hugepage/enabled")

# -----------------------------------------
# Summary
# -----------------------------------------
print(f"\n{'Parameter':<35} {'Bad Baseline':<15} {'Tuned':<15}")
print(f"{'-'*65}")
print(f"  {'vm.swappiness':<33} {'200':<15} {swappiness:<15}")
print(f"  {'vm.vfs_cache_pressure':<33} {'500':<15} {cache_pressure:<15}")
print(f"  {'vm.dirty_ratio':<33} {'5':<15} {dirty_ratio:<15}")
print(f"  {'vm.dirty_background_ratio':<33} {'2':<15} {dirty_bg:<15}")
print(f"  {'vm.min_free_kbytes':<33} {'16384':<15} {min_free:<15}")
print(f"  {'THP':<33} {'never':<15} {thp:<15}")

# -----------------------------------------
# Apply or print
# -----------------------------------------
if APPLY_MODE:
    print("\n--- Applying Tuning Commands Automatically ---")
    for cmd in commands:
        print(f"\n  [APPLY] {cmd}")
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"          ✓ Done")
        else:
            print(f"          ✗ FAILED: {result.stderr.strip()}")
    print("\n--- All Tuning Applied ---")
else:
    print("\n--- Commands to Apply ---")
    for cmd in commands:
        print(f"  {cmd}")

print("\n--- Reasons ---")
for r in reasons:
    print(f"  - {r}")
