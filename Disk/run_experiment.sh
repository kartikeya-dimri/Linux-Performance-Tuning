#!/bin/bash

# chmod +x run_experiment.sh
# ==========================================
# Full Experiment Pipeline
# ==========================================

WORKLOAD=$1

echo "=================================="
echo " Running Experiment: $WORKLOAD"
echo "=================================="

# -------------------------------
# BEFORE (Baseline under load)
# -------------------------------
echo "[1] Collecting BEFORE metrics..."
./run_monitoring.sh $WORKLOAD

BEFORE_DIR=$(ls -td run_* | head -1)

# Feature extraction
echo "[2] Extracting features (BEFORE)..."
python3 disk_features_full.py <<EOF
$BEFORE_DIR
EOF

# Classification
echo "[3] Classification (BEFORE)..."
python3 disk_classification.py <<EOF
$BEFORE_DIR/disk_features_full.json
EOF

# -------------------------------
# TUNING
# -------------------------------
echo "[4] Applying tuning..."
python3 disk_tuning.py <<EOF
sda
$BEFORE_DIR/disk_features_full.json
EOF

echo ">>> Apply the above commands manually, then press ENTER"
read

# -------------------------------
# AFTER (Post-tuning)
# -------------------------------
echo "[5] Collecting AFTER metrics..."
./run_monitoring.sh $WORKLOAD

AFTER_DIR=$(ls -td run_* | head -1)

# Feature extraction
echo "[6] Extracting features (AFTER)..."
python3 disk_features_full.py <<EOF
$AFTER_DIR
EOF

# -------------------------------
# PLOTTING
# -------------------------------
echo "[7] Generating comparison plots..."
python3 disk_plots.py <<EOF
$BEFORE_DIR
$AFTER_DIR
EOF

echo "=================================="
echo " Experiment Complete"
echo "=================================="
echo "Before: $BEFORE_DIR"
echo "After : $AFTER_DIR"
echo "Plots : comparison_plots/"