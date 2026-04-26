#!/usr/bin/env python3

import json

# -----------------------------------------
# Thresholds (analogous to disk_classification.py thresholds)
# -----------------------------------------
THRESHOLDS = {
    "low_free_mb":       200,    # < 200 MB free → memory pressure
    "high_swap_mb":      512,    # > 512 MB swap used → swap pressure
    "high_pgmajfault":   100,    # > 100 major faults/s → heavy paging
    "high_swap_rate":    10,     # > 10 KB/s swap in+out → active swapping
    "high_psi":          10.0,   # > 10 PSI some avg10 → memory stall
}

# -----------------------------------------
# Classification Logic
# -----------------------------------------
def classify_memory(features):
    reasons = []
    score   = 0

    free_mb  = features.get("avg_free_mb", 9999)
    swap_mb  = features.get("avg_swap_used_mb", 0)
    majfault = features.get("avg_pgmajfault", 0)
    swap_si  = features.get("avg_si_kBps", 0)
    swap_so  = features.get("avg_so_kBps", 0)
    psi      = features.get("psi_some_avg10", 0)

    if free_mb < THRESHOLDS["low_free_mb"]:
        reasons.append(f"Very low free memory ({free_mb:.0f} MB < {THRESHOLDS['low_free_mb']} MB)")
        score += 1

    if swap_mb > THRESHOLDS["high_swap_mb"]:
        reasons.append(f"High swap usage ({swap_mb:.0f} MB > {THRESHOLDS['high_swap_mb']} MB)")
        score += 1

    if majfault > THRESHOLDS["high_pgmajfault"]:
        reasons.append(f"High major page fault rate ({majfault:.1f}/s > {THRESHOLDS['high_pgmajfault']}/s)")
        score += 1

    if (swap_si + swap_so) > THRESHOLDS["high_swap_rate"]:
        reasons.append(f"Active swapping (si+so = {swap_si+swap_so:.1f} KB/s > {THRESHOLDS['high_swap_rate']} KB/s)")
        score += 1

    if psi > THRESHOLDS["high_psi"]:
        reasons.append(f"Memory PSI pressure ({psi:.2f} > {THRESHOLDS['high_psi']})")
        score += 1

    classification = "MEMORY-BOUND" if score >= 2 else "NOT MEMORY-BOUND"

    return classification, reasons, score


# -----------------------------------------
# Main
# -----------------------------------------
def main():
    path = input("Enter path to mem_features_full.json: ").strip()

    with open(path) as f:
        features = json.load(f)

    classification, reasons, score = classify_memory(features)

    print("\n==============================")
    print(" Memory Bottleneck Classification")
    print("==============================\n")

    print("Classification:", classification)

    if reasons:
        print("\nReasons:")
        for r in reasons:
            print("-", r)

    print("\nConfidence Score:", score, "/ 5")

    if classification == "MEMORY-BOUND":
        print("\nSuggested Actions:")
        print("- Reduce vm.swappiness (e.g., sysctl -w vm.swappiness=10)")
        print("- Adjust dirty_ratio/dirty_background_ratio")
        print("- Enable Transparent Huge Pages (thp=always or madvise)")
        print("- Add more RAM or create/expand swap")
        print("- Check for memory leaks with 'smem' or 'pmap'")


if __name__ == "__main__":
    main()
