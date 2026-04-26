#!/bin/bash

echo "[+] Resetting system state between runs..."

# Step 1: Sync dirty pages to disk
echo "    [1/3] Syncing dirty pages to disk (sudo sync)..."
sudo sync
echo "    [1/3] Sync done."

# Step 2: Drop page cache, dentries, and inodes
echo "    [2/3] Dropping page/dentry/inode caches..."
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
echo "    [2/3] Caches dropped."

# Step 3: Brief settle time
echo "    [3/3] Settling (3s)..."
sleep 3

echo "[+] System reset complete."
echo ""

# NOTE: We intentionally skip 'swapoff -a && swapon -a' here.
# swapoff blocks until ALL swap data is moved back to RAM,
# which can take many minutes (or OOM) on a memory-pressured VM.
# Dropping page cache + a short sleep is sufficient to get a
# reproducible starting state between baseline and tuned runs.
