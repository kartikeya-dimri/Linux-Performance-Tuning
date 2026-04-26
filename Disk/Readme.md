# Disk I/O Performance Tuning Experiment

A controlled experiment to demonstrate that **intelligent I/O scheduler and read-ahead tuning** can significantly improve disk performance across random, sequential, and mixed workloads on Linux.

## Overview

The pipeline:
1. **Applies a deliberately bad baseline** config (wrong scheduler + wrong read-ahead for the workload)
2. **Runs a fio workload** while collecting system metrics (iostat, vmstat, pidstat, PSI)
3. **Extracts features** from the collected data and classifies the workload
4. **Recommends tuning** based on detected workload type and queue depth
5. **Re-runs the same workload** with the tuned config
6. **Generates comparison plots** showing before vs after

See [Results.md](Results.md) for the full experiment results.

## Prerequisites

- **Linux VM** (tested on Ubuntu with VirtualBox, disk device `sda`)
- **Root/sudo access** (required for changing scheduler and read-ahead)
- **fio** — flexible I/O tester (`sudo apt install fio`)
- **sysstat** — provides `iostat`, `mpstat`, `pidstat` (`sudo apt install sysstat`)
- **Python 3** with `pandas` and `matplotlib` (`pip3 install pandas matplotlib`)
- **~5 GB free disk space** (for the 4 GB test file + logs)

## Quick Start

```bash
# Run the full experiment for a workload type
./run_experiment.sh rand    # Random 4K reads
./run_experiment.sh seq     # Sequential 1M reads
./run_experiment.sh mix     # Mixed 4K random read/write (70/30)
```

The script will:
1. Reset caches and apply a bad baseline config
2. Run the baseline workload (90 seconds)
3. Extract features and recommend tuning
4. **Pause** — you must apply the tuning commands manually, then press ENTER
5. Reset caches and run the tuned workload (90 seconds)
6. Generate comparison plots

> **Note:** When prompted, manually run the two tuning commands printed on screen (e.g., `echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler` and `sudo blockdev --setra 128 /dev/sda`), then press ENTER to continue.

## Directory Structure

```
Disk/
├── run_experiment.sh          # Main entry point — runs full baseline → tune → compare pipeline
├── run_monitoring.sh          # Starts background monitors (iostat, vmstat, pidstat, PSI), runs workload, collects logs
├── run_workload.sh            # fio workload definitions (rand, seq, mix)
├── reset_system.sh            # Flushes page cache (sync + drop_caches)
│
├── disk_features_full.py      # Parses iostat/vmstat/pidstat/PSI logs → extracts feature JSON
├── disk_tuning.py             # Reads feature JSON → detects workload → recommends scheduler + read-ahead
├── disk_classification.py     # Classifies system as DISK-BOUND or NOT based on feature thresholds
├── disk_plots.py              # Generates before/after comparison bar charts
│
├── disk_baseline_full.sh      # Standalone feature extraction script (same logic as disk_features_full.py)
├── run_baseline.sh            # Standalone baseline runner (without tuning step)
├── run_tuned.sh               # Standalone tuned workload runner
├── run_analysis.sh            # Standalone plot generator
├── set_baseline.sh            # Applies default safe baseline config (mq-deadline + RA 128)
│
├── run_before/                # Baseline run output (generated)
│   ├── iostat.log             # Raw iostat output
│   ├── iostat_clean.log       # Cleaned iostat (no headers/blanks)
│   ├── vmstat.log             # Raw vmstat output
│   ├── vmstat_clean.log       # Cleaned vmstat
│   ├── pidstat.log            # Per-process I/O stats
│   ├── mpstat.log             # CPU stats
│   ├── psi_io.log             # Pressure Stall Information snapshots
│   ├── disk_features_full.json # Extracted feature summary
│   ├── system_info.txt        # uname -a
│   ├── disk_layout.txt        # lsblk
│   ├── filesystem_usage.txt   # df -h
│   └── memory_snapshot.txt    # free -m
│
├── run_after/                 # Tuned run output (same structure as run_before/)
│
├── comparison_plots_ran/      # Random workload plots
│   ├── avg_await.png
│   ├── avg_iops.png
│   ├── avg_iowait.png
│   ├── avg_queue.png
│   └── avg_util.png
├── comparison_plots_seq/      # Sequential workload plots
├── comparison_plots_mix/      # Mixed workload plots
│
├── Results.md                 # Detailed experiment results with tables
├── logs.txt                   # Raw terminal logs from first experiment run
├── logs2.txt                  # Raw terminal logs from final experiment run
└── Readme.md                  # This file
```

## Script Details

### Core Pipeline

| Script | Purpose |
|--------|---------|
| `run_experiment.sh <workload>` | Full pipeline: baseline → feature extraction → tuning recommendation → tuned run → plots |
| `run_monitoring.sh <workload> <output_dir>` | Starts iostat/vmstat/pidstat/PSI in background, runs the fio workload, stops monitors, cleans logs |
| `run_workload.sh <workload>` | Runs the fio workload (`rand`, `seq`, or `mix`) against a 4 GB test file |
| `reset_system.sh` | Syncs and drops page cache to ensure clean state between runs |

### Analysis Scripts

| Script | Purpose |
|--------|---------|
| `disk_features_full.py` | Parses all log files and computes: avg latency, queue depth, utilization, IOPS, throughput, iowait, request size, write ratio, top I/O process, PSI pressure, and a composite disk pressure score |
| `disk_tuning.py` | Reads extracted features, detects workload type (random/sequential/mixed), and recommends I/O scheduler + read-ahead settings |
| `disk_classification.py` | Standalone classifier — determines if the system is disk-bound based on threshold checks |
| `disk_plots.py` | Generates before/after bar charts for key metrics |

### Standalone Scripts

| Script | Purpose |
|--------|---------|
| `run_baseline.sh` | Runs just the baseline step (reset → default config → monitor + workload → extract features) |
| `run_tuned.sh` | Runs just the tuned workload step |
| `run_analysis.sh` | Generates plots from existing `run_before/` and `run_after/` data |
| `set_baseline.sh` | Applies a safe default config (`mq-deadline`, read-ahead 128) |

## Workload Configurations

| Workload | fio Mode | Block Size | Jobs | I/O Depth | Duration |
|----------|----------|------------|------|-----------|----------|
| `rand` | `randread` | 4 KB | 4 | 64 | 90s |
| `seq` | `read` | 1 MB | 2 | 64 | 90s |
| `mix` | `randrw` (70R/30W) | 4 KB | 4 | 64 | 90s |

All workloads use `direct=1` (bypass page cache) and `libaio` engine against a 4 GB test file.

## Tuning Logic

The tuning script classifies the workload and selects parameters:

**Workload Detection:**
- `write_ratio > 0.15` → **mixed**
- `avg_req_size > 128 KB` → **sequential**
- `avg_req_size < 32 KB` → **random**

**Scheduler Selection:**
- `avg_queue > 50` → `mq-deadline` (reorder requests for fairness)
- Otherwise → `none` (minimize overhead)

**Read-Ahead Selection:**
- Sequential → `1024` (aggressive prefetching)
- Mixed → `512` (moderate compromise)
- Random → `128` (minimize wasted prefetch)

## Bad Baselines (Deliberate Misconfiguration)

To demonstrate tuning impact, each workload starts with a config that is wrong for that specific pattern:

| Workload | Bad Config | Why It's Bad |
|----------|-----------|--------------|
| `rand` | `none` + RA 1024 | No reordering + wasteful prefetching for random 4K I/O |
| `seq` | `none` + RA 32 | No reordering + starved prefetch pipeline for 1M sequential reads |
| `mix` | `none` + RA 4096 | No read/write fairness + massive wasted prefetch for 4K mixed I/O |

## Reproducing Results

```bash
# 1. Clone the repo
git clone https://github.com/kartikeya-dimri/Linux-Disk.git
cd Linux-Disk

# 2. Install dependencies
sudo apt install fio sysstat
pip3 install pandas matplotlib

# 3. Make scripts executable
chmod +x *.sh

# 4. Run all three experiments
./run_experiment.sh rand
# (apply tuning when prompted, press ENTER)

./run_experiment.sh seq
# (apply tuning when prompted, press ENTER)

rm -rf run_before run_after   # clean between experiments
./run_experiment.sh mix
# (apply tuning when prompted, press ENTER)

# 5. Check results
# - Plots in comparison_plots_*/
# - Features in run_before/disk_features_full.json and run_after/disk_features_full.json
# - Full results in Results.md
```

> **Important:** Run `rm -rf run_before run_after` between experiments to avoid mixing data from different workloads. The plots are saved to workload-specific directories (`comparison_plots_ran/`, `comparison_plots_seq/`, `comparison_plots_mix/`) and will not be overwritten.
