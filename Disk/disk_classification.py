#!/usr/bin/env python3

import json

# -----------------------------------------
# Thresholds
# -----------------------------------------
THRESHOLDS = {
    "high_util": 70,
    "high_iowait": 10,
    "high_latency": 10,
    "high_queue": 1,
    "high_psi": 0.1
}

# -----------------------------------------
# Classification Logic
# -----------------------------------------
def classify_disk(features):
    reasons = []
    score = 0

    if features.get("avg_util", 0) > THRESHOLDS["high_util"]:
        reasons.append("High disk utilization")
        score += 1

    if features.get("avg_iowait", 0) > THRESHOLDS["high_iowait"]:
        reasons.append("High CPU iowait")
        score += 1

    if features.get("avg_await", 0) > THRESHOLDS["high_latency"]:
        reasons.append("High disk latency")
        score += 1

    if features.get("avg_queue", 0) > THRESHOLDS["high_queue"]:
        reasons.append("High disk queue")
        score += 1

    if features.get("psi_some_avg10", 0) > THRESHOLDS["high_psi"]:
        reasons.append("I/O pressure (PSI)")
        score += 1

    if score >= 2:
        classification = "DISK-BOUND"
    else:
        classification = "NOT DISK-BOUND"

    return classification, reasons, score


# -----------------------------------------
# Main
# -----------------------------------------
def main():
    path = input("Enter path to disk_features_full.json: ").strip()

    with open(path) as f:
        features = json.load(f)

    classification, reasons, score = classify_disk(features)

    print("\n==============================")
    print(" Disk Bottleneck Classification")
    print("==============================\n")

    print("Classification:", classification)

    if reasons:
        print("\nReasons:")
        for r in reasons:
            print("-", r)

    if "top_io_process" in features:
        print("\nTop I/O Process:")
        print("-", features["top_io_process"], f"({round(features.get('top_io_kB',0),2)} kB)")

    print("\nConfidence Score:", score, "/ 5")

    if classification == "DISK-BOUND":
        print("\nSuggested Actions:")
        print("- Tune I/O scheduler")
        print("- Increase read-ahead (if sequential)")
        print("- Reduce random I/O")
        print("- Check caching")


if __name__ == "__main__":
    main()