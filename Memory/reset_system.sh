#!/bin/bash

echo "[+] Resetting system..."

# Drop page/dentry/inode caches
sudo sync
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null

# Flush swap (swapoff + swapon resets swap usage to zero)
sudo swapoff -a 2>/dev/null && sudo swapon -a 2>/dev/null

sleep 3

echo "[+] System reset complete."
