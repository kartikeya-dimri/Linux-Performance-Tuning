#!/bin/bash

echo "[+] Setting safe baseline memory configuration..."

# Moderate swappiness (kernel default)
sudo sysctl -w vm.swappiness=60

# Reasonable dirty page write-back thresholds
sudo sysctl -w vm.dirty_ratio=20
sudo sysctl -w vm.dirty_background_ratio=10

# THP: madvise (safe default — only use when process asks)
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null

echo "[+] Baseline configuration applied."

# Verify
echo ""
echo "[+] Current settings:"
sysctl vm.swappiness vm.dirty_ratio vm.dirty_background_ratio
cat /sys/kernel/mm/transparent_hugepage/enabled
