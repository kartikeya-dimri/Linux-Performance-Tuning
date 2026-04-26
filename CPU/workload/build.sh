#!/usr/bin/env bash
# build.sh — Compile prime.c
# Place this at: CPU/workload/build.sh
# Run: bash build.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[build] Compiling prime.c ..."

gcc -O2 -o prime prime.c -lpthread -lm

echo "[build] Done. Binary: $(pwd)/prime"
echo "[build] Quick test: taskset -c 0,1 ./prime 2"
