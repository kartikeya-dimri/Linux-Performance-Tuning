# Memory Performance Tuning Experiment

A controlled experiment to demonstrate that **intelligent memory parameter tuning** (swappiness, dirty write-back thresholds, and Transparent Huge Pages) can significantly reduce memory pressure across allocation-heavy, cache-thrashing, and mixed workloads on Linux.

## Overview

The pipeline:
1. **Applies a deliberately bad baseline** config (wrong swappiness + dirty_ratio + THP setting for the workload)
2. **Runs a stress-ng workload** while collecting system metrics (vmstat, /proc/meminfo, /proc/vmstat, PSI)
3. **Extracts features** from the collected data and classifies the workload
4. **Recommends tuning** based on detected memory pressure type
5. **Re-runs the same workload** with the tuned config
6. **Generates comparison plots** showing before vs after

See [Results.md](Results.md) for the full experiment results.

## Prerequisites

- **Linux VM** (tested on Ubuntu with VirtualBox)
- **Root/sudo access** (required for sysctl and THP changes)
- **stress-ng** — memory workload generator (`sudo apt install stress-ng`)
- **sysstat** — provides `vmstat` (`sudo apt install sysstat`)
- **Python 3** with `pandas`, `matplotlib`, `scipy`, `numpy` (`pip3 install pandas matplotlib scipy numpy`)
- **A swap partition or swap file** (needed for swappiness experiments)
  - Create one if needed: `sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`

## Quick Start

```bash
# Run the full experiment for a workload type
./run_experiment.sh alloc    # Anonymous memory allocation pressure
./run_experiment.sh cache    # Page cache / CPU cache thrash
./run_experiment.sh mix      # Combined alloc + cache
```

The script will:
1. Apply a bad baseline config
2. Run the baseline workload (90 seconds) while collecting metrics
3. Extract features and recommend tuning
4. **Pause** — you must apply the tuning commands printed on screen, then press ENTER
5. Reset memory state and run the tuned workload (90 seconds)
6. Generate comparison plots

> **Note:** When prompted, manually run the sysctl commands and THP echo printed on screen (e.g., `sudo sysctl -w vm.swappiness=10` and `echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled`), then press ENTER.

## Directory Structure

```
Memory/
├── run_experiment.sh          # Main entry point — runs full baseline → tune → compare pipeline
├── run_monitoring.sh          # Starts background monitors (vmstat, /proc/meminfo, /proc/vmstat, PSI), runs workload
├── run_workload.sh            # stress-ng workload definitions (alloc, cache, mix)
├── reset_system.sh            # Drops page cache + flushes swap
│
├── mem_features_full.py       # Parses vmstat/meminfo/proc-vmstat/PSI logs → extracts feature JSON
├── mem_tuning.py              # Reads feature JSON → detects workload → recommends memory parameters
├── mem_classification.py      # Standalone classifier — determines if system is MEMORY-BOUND
├── mem_plots.py               # Generates before/after comparison bar charts
├── mem_stats.py               # Intra-run (Mann-Whitney U) + Inter-run (Welch's t-test) stats
│
├── run_baseline.sh            # Standalone baseline runner
├── run_tuned.sh               # Standalone tuned workload runner
├── run_analysis.sh            # Standalone plot generator
├── run_repeated.sh            # Repeated experiment runner (N iterations for statistical validity)
├── set_baseline.sh            # Applies safe default memory config
│
├── run_before/                # Baseline run output (generated at runtime)
│   ├── vmstat.log             # Raw vmstat output
│   ├── vmstat_clean.log       # Cleaned vmstat (no headers/blanks)
│   ├── meminfo.log            # Periodic /proc/meminfo snapshots
│   ├── vmstat_proc.log        # Periodic /proc/vmstat snapshots (pgfault, swap counters)
│   ├── psi_mem.log            # /proc/pressure/memory snapshots
│   ├── mem_features_full.json # Extracted feature summary
│   ├── system_info.txt        # uname -a
│   └── memory_snapshot.txt    # free -m
│
├── run_after/                 # Tuned run output (same structure as run_before/)
│
├── comparison_plots_alloc/    # Anonymous alloc workload plots
│   ├── avg_free_mb.png
│   ├── avg_pgmajfault.png
│   ├── avg_si_kBps.png
│   ├── avg_so_kBps.png
│   └── psi_some_avg10.png
├── comparison_plots_cache/    # Cache workload plots
├── comparison_plots_mix/      # Mixed workload plots
│
├── Results.md                 # Detailed experiment results with tables
├── logs.txt                   # Raw terminal logs (generated after running)
└── Readme.md                  # This file
```

## Script Details

### Core Pipeline

| Script | Purpose |
|--------|---------|
| `run_experiment.sh <workload>` | Full pipeline: bad baseline → monitoring → feature extraction → tuning recommendation → tuned run → plots + stats |
| `run_monitoring.sh <workload> <output_dir>` | Starts vmstat + /proc/meminfo + /proc/vmstat + PSI in background, runs the stress-ng workload, stops monitors, cleans logs |
| `run_workload.sh <workload>` | Runs the stress-ng workload (`alloc`, `cache`, or `mix`) for 90 seconds |
| `reset_system.sh` | Drops page cache and flushes swap to ensure clean state between runs |

### Analysis Scripts

| Script | Purpose |
|--------|---------|
| `mem_features_full.py` | Parses all log files and computes: avg free memory, swap usage, major page faults/s, swap in/out rates, page cache size, PSI pressure, and a composite memory pressure score |
| `mem_tuning.py` | Reads extracted features, detects workload type (swap-heavy/fault-heavy/mixed), and recommends vm.swappiness + dirty_ratio + THP settings |
| `mem_classification.py` | Standalone classifier — determines if the system is memory-bound based on 5 threshold checks |
| `mem_plots.py` | Generates before/after bar charts for 5 key memory metrics with % change annotation |
| `mem_stats.py` | Mann-Whitney U for intra-run time-series significance; Welch's t-test for inter-run feature aggregates |

### Standalone Scripts

| Script | Purpose |
|--------|---------|
| `run_baseline.sh` | Runs just the baseline step (reset → safe default config → monitor + workload → extract features) |
| `run_tuned.sh` | Runs just the tuned workload step |
| `run_analysis.sh` | Generates plots from existing `run_before/` and `run_after/` data |
| `run_repeated.sh <workload> <N>` | Runs N full iterations for inter-run statistical analysis |
| `set_baseline.sh` | Applies safe default config (swappiness=60, dirty_ratio=20, thp=madvise) |

## Workload Configurations

| Workload | Tool | Stress Pattern | Jobs | Duration | Simulates |
|----------|------|---------------|------|----------|-----------|
| `alloc` | stress-ng `--vm` | Anonymous malloc/free, 75% RAM | 4 | 90s | JVM heap, malloc-heavy apps |
| `cache` | stress-ng `--cache` | L1/L2/L3 + page cache thrash, 256M | 4 | 90s | Database buffer pool, file servers |
| `mix` | stress-ng `--vm` + `--cache` | 2 VM workers + 2 cache workers | 4 | 90s | Real-world mixed memory workload |

## Tuning Logic

The tuning script classifies the workload and selects parameters:

**Workload Detection:**
- `avg_si_kBps + avg_so_kBps > 20` AND `avg_pgmajfault > 50` → **mixed**
- `avg_si_kBps + avg_so_kBps > 20` → **swap-heavy**
- `avg_pgmajfault > 50` → **fault-heavy**

**vm.swappiness:**
- `avg_free_mb < 200` or `avg_swap_used_mb > 512` → `10` (aggressive reduction)
- Otherwise → `30` (moderate reduction)

**vm.dirty_ratio / vm.dirty_background_ratio:**
- swap-heavy → `20 / 10` (larger buffer to reduce flush-triggered eviction)
- fault-heavy → `15 / 5` (moderate buffer)
- mixed → `20 / 10` (safe compromise)

**Transparent Huge Pages (THP):**
- swap-heavy (anon-dominant) → `always` (reduce TLB pressure on large allocations)
- fault-heavy or mixed → `madvise` (avoid compaction overhead)

## Bad Baselines (Deliberate Misconfiguration)

To demonstrate tuning impact, all workloads start with the same bad config:

| Parameter | Bad Value | Why It's Bad |
|-----------|----------|-------------|
| `vm.swappiness` | 80 | Aggressively evicts anonymous pages even when RAM is available |
| `vm.dirty_ratio` | 5 | Flushes dirty pages too eagerly, causing write stalls |
| `vm.dirty_background_ratio` | 2 | Background flusher too aggressive, interrupts foreground writes |
| THP | `never` | Disables huge pages, increasing TLB pressure for large allocations |

## Reproducing Results

```bash
# 1. Clone the repo
git clone <repo-url>
cd Memory/

# 2. Install dependencies
sudo apt install stress-ng sysstat
pip3 install pandas matplotlib scipy numpy

# 3. (If no swap exists) Create a swap file
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 4. Make scripts executable
chmod +x *.sh

# 5. Run all three experiments
./run_experiment.sh alloc
# (apply tuning when prompted, press ENTER)

rm -rf run_before run_after
./run_experiment.sh cache
# (apply tuning when prompted, press ENTER)

rm -rf run_before run_after
./run_experiment.sh mix
# (apply tuning when prompted, press ENTER)

# 6. Check results
# - Plots in comparison_plots_*/
# - Features in run_before/mem_features_full.json and run_after/mem_features_full.json
# - Full results in Results.md
```

> **Important:** Run `rm -rf run_before run_after` between experiments to avoid mixing data from different workloads. The plots are saved to workload-specific directories and will not be overwritten.

## Key Metrics Explained

| Metric | Source | What it measures |
|--------|--------|-----------------|
| `avg_free_mb` | `/proc/meminfo` | Average free RAM — lower = more pressure |
| `avg_pgmajfault` | `/proc/vmstat` delta | Major page faults/s — process fetched page from disk |
| `avg_si_kBps` | `vmstat` si column | Pages swapped IN per second (KB) |
| `avg_so_kBps` | `vmstat` so column | Pages swapped OUT per second (KB) |
| `avg_cache_mb` | `/proc/meminfo` | Cached + Buffers in MB — lower = cache eviction |
| `psi_some_avg10` | `/proc/pressure/memory` | % time at least one task was stalled on memory (10s avg) |
| `memory_pressure_score` | Derived | Weighted composite (swap rate 25% + majfault 25% + iowait 25% + PSI 25%) |
