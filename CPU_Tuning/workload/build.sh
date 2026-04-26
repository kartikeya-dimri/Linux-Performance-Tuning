#!/usr/bin/env bash
# build.sh — Compile prime.c
# Run from: CPU_Tuning/  →  bash workload/build.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[build] Compiling prime.c ..."
gcc -O2 -o prime prime.c -lpthread -lm
echo "[build] Done → $(pwd)/prime"
echo ""
echo "[build] Sanity test — single process on cpu7 (~14s expected):"
taskset -c 7 ./prime 2