#!/bin/bash

echo "[+] Resetting system..."

sudo sync
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null

sleep 5

echo "[+] System reset complete."