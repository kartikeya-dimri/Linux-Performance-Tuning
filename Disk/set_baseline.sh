#!/bin/bash

DEVICE="sda"

echo "[+] Setting baseline configuration..."

# Use safe default scheduler
echo mq-deadline | sudo tee /sys/block/$DEVICE/queue/scheduler > /dev/null

# Default read-ahead
sudo blockdev --setra 128 /dev/$DEVICE

echo "[+] Baseline configuration applied"

# Verify
cat /sys/block/$DEVICE/queue/scheduler
sudo blockdev --getra /dev/$DEVICE