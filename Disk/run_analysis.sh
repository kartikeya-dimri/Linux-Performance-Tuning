#!/bin/bash

echo "[+] Generating comparison plots..."

echo -e "run_before\nrun_after" | python3 disk_plots.py

echo "[+] Done. See comparison_plots/"