#!/bin/bash

echo "[+] Setting safe baseline memory configuration..."

sudo sysctl -w vm.swappiness=60
sudo sysctl -w vm.vfs_cache_pressure=100
sudo sysctl -w vm.dirty_ratio=20
sudo sysctl -w vm.dirty_background_ratio=10
sudo sysctl -w vm.min_free_kbytes=65536
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null

echo "[+] Baseline configuration applied."
echo ""
echo "[+] Current settings:"
sysctl vm.swappiness vm.vfs_cache_pressure vm.dirty_ratio vm.dirty_background_ratio vm.min_free_kbytes
cat /sys/kernel/mm/transparent_hugepage/enabled
