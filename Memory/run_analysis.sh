#!/bin/bash

echo "[+] Generating comparison plots..."

echo -e "run_before\nrun_after\nmix" | python3 mem_plots.py

echo "[+] Done. See comparison_plots_*/"
