#!/usr/bin/env python3

import json

# -----------------------------------------
# Thresholds (tunable, but grounded)
# -----------------------------------------
THRESHOLDS = {
    "high_util": 70,          # %
    "high_iowait": 10,        # %
    "high_latency": 10,       # ms (device dependent)
    "high_queue": 1,          # avg queue depth
    "high_psi": 0.1           # avg10 stall %
}

# -----------------------------------------
# Classification Logic
# -----------------------------------------
def classify_disk(features):
    reasons = []
    score = 0

    # Utilization
    if features.get("avg_util", 0) > THRESHOLDS["high_util"]:
        reasons.append("High disk utilization")
        score += 1

    # I/O wait
    if features.get("avg_iowait", 0) > THRESHOLDS["high_iowait"]:
        reasons.append("High CPU iowait (CPU blocked on disk)")
        score += 1

    # Latency
    if features.get("avg_await", 0) > THRESHOLDS["high_latency"]:
        reasons.append("High disk latency")
        score += 1

    # Queue saturation
    if features.get("avg_queue", 0) > THRESHOLDS["high_queue"]:
        reasons.append("High disk queue (saturation)")
        score += 1

    # PSI pressure
    if features.get("psi_some_avg10", 0) > THRESHOLDS["high_psi"]:
        reasons.append("I/O pressure (tasks stalled on disk)")
        score += 1

    # -------------------------------------
    # Final Decision
    # -------------------------------------
    if score >= 2:
        classification = "DISK-BOUND"
    else:
        classification = "NOT DISK-BOUND"

    return classification, reasons, score


# -----------------------------------------
# Interpretation Layer
# -----------------------------------------
def explain(features, classification, reasons):
    explanation = []

    explanation.append(f"Classification: {classification}")

    if reasons:
        explanation.append("\nReasons:")
        for r in reasons:
            explanation.append(f"- {r}")

    # Additional insight
    if "top_io_process" in features:
        explanation.append("\nTop I/O Process:")
        explanation.append(
            f"- {features['top_io_process']} ({round(features.get('top_io_kB',0),2)} kB)"
        )

    # Latency insight
    if "avg_r_await" in features and "avg_w_await" in features:
        explanation.append("\nLatency Breakdown:")
        explanation.append(f"- Read latency : {round(features['avg_r_await'],2)} ms")
        explanation.append(f"- Write latency: {round(features['avg_w_await'],2)} ms")

    return "\n".join(explanation)


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

    print(explain(features, classification, reasons))

    print("\nConfidence Score:", score, "/ 5")

    # Optional: suggest tuning
    if classification == "DISK-BOUND":
        print("\nSuggested Actions:")
        print("- Tune I/O scheduler (mq-deadline / none for NVMe)")
        print("- Increase read-ahead (if sequential workload)")
        print("- Reduce random I/O or batch operations")
        print("- Check caching / application I/O patterns")


if __name__ == "__main__":
    main()