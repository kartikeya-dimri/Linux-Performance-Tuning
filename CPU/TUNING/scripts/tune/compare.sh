#!/bin/bash
# ============================================================
# compare.sh — Baseline vs After-Tuning comparison
# ============================================================
# Usage: ./compare.sh
#
# Reads:
#   baseline/summary.txt
#   after_tuning/experiment_*/summary.txt
#
# Outputs:
#   results/comparison.txt  — full table + analysis
#   (also prints to stdout)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

BASELINE="$PROJECT_ROOT/baseline/summary.txt"
AFTER_DIR="$PROJECT_ROOT/after_tuning"
RESULTS_DIR="$PROJECT_ROOT/results"

mkdir -p "$RESULTS_DIR"
OUTPUT="$RESULTS_DIR/comparison.txt"

# ── Validate baseline exists ─────────────────────────────────
if [[ ! -f "$BASELINE" ]]; then
    echo "ERROR: baseline/summary.txt not found. Run run_baseline.sh first." >&2
    exit 1
fi

# ── Run comparison in Python ─────────────────────────────────
python3 - "$BASELINE" "$AFTER_DIR" "$OUTPUT" <<'PYEOF'
import sys, os, statistics, glob

baseline_file, after_dir, output_file = sys.argv[1], sys.argv[2], sys.argv[3]

# ── Parse a summary.txt → dict of metric → mean ─────────────
def parse_summary(path):
    result = {}
    current_label = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.endswith(":"):
                current_label = line[:-1].strip()
            elif line.startswith("mean") and current_label:
                result[current_label] = float(line.split("=")[1].strip())
    return result

baseline = parse_summary(baseline_file)
baseline_elapsed = baseline.get("elapsed_time (s)", None)
baseline_cpu     = baseline.get("cpu_util    (%)", None)

if baseline_elapsed is None:
    print("ERROR: Could not parse baseline elapsed_time", file=sys.stderr)
    sys.exit(1)

# ── Find all experiment summary files ────────────────────────
pattern = os.path.join(after_dir, "experiment_*", "summary.txt")
exp_files = sorted(glob.glob(pattern))

if not exp_files:
    print("ERROR: No experiment results found in after_tuning/", file=sys.stderr)
    print("Run tune.sh first.", file=sys.stderr)
    sys.exit(1)

# ── Build report ─────────────────────────────────────────────
lines = []
lines.append("=" * 60)
lines.append("  CPU TUNING COMPARISON REPORT")
lines.append(f"  Generated: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
lines.append("=" * 60)
lines.append("")
lines.append(f"BASELINE")
lines.append(f"  elapsed mean : {baseline_elapsed:.4f}s")
lines.append(f"  cpu_util mean: {baseline_cpu:.1f}%")
lines.append("")
lines.append("-" * 60)

best_improvement = 0
best_label = ""

for exp_file in exp_files:
    # Get experiment label from folder name
    folder = os.path.basename(os.path.dirname(exp_file))
    label  = folder.replace("experiment_", "").replace("_", " ").title()

    exp = parse_summary(exp_file)
    exp_elapsed = exp.get("elapsed_time (s)", None)
    exp_cpu     = exp.get("cpu_util    (%)", None)

    if exp_elapsed is None:
        lines.append(f"[{label}] — could not parse results")
        continue

    improvement = ((baseline_elapsed - exp_elapsed) / baseline_elapsed) * 100
    speedup     = baseline_elapsed / exp_elapsed

    lines.append(f"EXPERIMENT: {label}")
    lines.append(f"  elapsed mean   : {exp_elapsed:.4f}s")
    lines.append(f"  cpu_util mean  : {exp_cpu:.1f}%")
    lines.append(f"  improvement    : {improvement:+.2f}%")
    lines.append(f"  speedup        : {speedup:.2f}x")

    # Flag if this is noise vs real improvement
    if abs(improvement) < 1.0:
        lines.append(f"  verdict        : ⚠️  marginal (< 1% — likely noise)")
    elif improvement > 0:
        lines.append(f"  verdict        : ✅ real improvement")
    else:
        lines.append(f"  verdict        : ❌ regression — tuning made it worse")

    if improvement > best_improvement:
        best_improvement = improvement
        best_label = label

    lines.append("")

lines.append("-" * 60)
lines.append("CONCLUSION")
if best_improvement > 1.0:
    lines.append(f"  Best tuning    : {best_label}")
    lines.append(f"  Improvement    : {best_improvement:.2f}%")
    lines.append(f"  Resume line    : 'Reduced CPU execution time by {best_improvement:.0f}%'")
    lines.append(f"                   'using [technique] on Intel Core Ultra 5 125H'")
else:
    lines.append("  No significant improvement found across experiments.")
    lines.append("  Consider increasing INTENSITY or DURATION for more signal.")
lines.append("=" * 60)

report = "\n".join(lines)
print(report)

with open(output_file, "w") as f:
    f.write(report + "\n")

print(f"\nSaved → {output_file}")
PYEOF
