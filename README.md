# Linux Performance Tuning

> **Authors:** Kartikeya Dimri · Ayush Mishra · Harsh Sinha  
> **Advisor:** Prof. B. Thangaraju  

A systematic experimental study of Linux performance bottlenecks and tuning strategies across three subsystems: **CPU scheduling**, **memory management**, and **disk I/O**. Each subsystem is studied independently under controlled stress workloads, using deliberate worst-case baselines to make the impact of targeted tuning decisions clearly measurable.

---

## Table of Contents

1. [Repository Structure](#repository-structure)
2. [Methodology](#methodology)
3. [CPU Tuning](#cpu-tuning)
4. [Memory Tuning](#memory-tuning)
5. [Disk I/O Tuning](#disk-io-tuning)
6. [Results Summary](#results-summary)
7. [Prerequisites](#prerequisites)
8. [Reproducing Results](#reproducing-results)

---

## Repository Structure

```
Linux-Performance-Tuning/
├── CPU/
│   ├── workload/
│   │   ├── prime.c                  # Deterministic CPU-bound stressor
│   │   ├── prime                    # Compiled binary (after build)
│   │   └── build.sh
│   ├── scripts/
│   │   ├── common.sh                # Shared config + measure_run() helper
│   │   ├── run_baselines.sh         # Collect SB (contention baseline)
│   │   ├── run_experiments.sh       # Collect C1 (affinity) and C2 (scheduler)
│   │   └── analyze.sh               # Stats, plots, final report
│   └── results/
│       ├── raw/                     # SB.csv, C1.csv, C2.csv
│       └── plots/                   # 6 PNG plots
│
├── Memory/
│   ├── run_experiment.sh            # Main pipeline: bad baseline → tune → compare
│   ├── run_monitoring.sh            # Background monitors + workload execution
│   ├── run_workload.sh              # stress-ng workload definitions
│   ├── reset_system.sh              # Drop page cache + flush swap
│   ├── mem_features_full.py         # Parses logs → feature JSON
│   ├── mem_tuning.py                # Feature JSON → tuning recommendation
│   ├── mem_classification.py        # MEMORY-BOUND classifier
│   ├── mem_plots.py                 # Before/after bar charts
│   ├── mem_stats.py                 # Mann-Whitney U + Welch's t-test
│   ├── run_before/                  # Baseline run output
│   ├── run_after/                   # Tuned run output
│   ├── comparison_plots_alloc/
│   ├── comparison_plots_cache/
│   └── comparison_plots_mix/
│
├── Disk/
│   ├── run_experiment.sh            # Main pipeline: bad baseline → tune → compare
│   ├── run_monitoring.sh            # iostat/vmstat/pidstat/PSI + workload
│   ├── run_workload.sh              # fio workload definitions (rand/seq/mix)
│   ├── reset_system.sh              # Sync + drop_caches
│   ├── disk_features_full.py        # Parses logs → feature JSON
│   ├── disk_tuning.py               # Feature JSON → scheduler + read-ahead recommendation
│   ├── disk_classification.py       # DISK-BOUND classifier
│   ├── disk_plots.py                # Before/after bar charts
│   ├── run_before/                  # Baseline run output
│   ├── run_after/                   # Tuned run output
│   ├── comparison_plots_ran/
│   ├── comparison_plots_seq/
│   └── comparison_plots_mix/
│
├── README.md                        # This file
└── run_cache.log
```

---

## Methodology

All three subsystems follow the same six-step experimental pipeline:

1. **Establish a bad baseline** — deliberately suboptimal configuration chosen to expose worst-case behavior for that subsystem.
2. **Run a subsystem-specific stress workload** — CPU-bound prime counting, memory-oversubscribed `stress-ng`, or direct-I/O `fio`.
3. **Collect metrics** — execution time, page faults, IOPS, latency, PSI pressure, etc.
4. **Extract features and classify** — Python scripts parse raw logs into structured JSON; rule-based logic detects workload type.
5. **Apply targeted tuning** — manually apply the printed tuning commands, then press ENTER to continue.
6. **Re-run and compare** — same workload under the tuned config; plots and stats generated automatically.

CPU experiments ran on a **physical machine** (Intel Core Ultra 5 125H, 14 cores) to avoid virtualization effects on scheduling. Memory and Disk experiments ran on a **VirtualBox VM** (8 GB RAM, `sda`) for controlled, reproducible conditions.

---

## CPU Tuning

**Goal:** Demonstrate that CPU affinity and real-time scheduler tuning are orthogonal fixes for two separate performance problems — core contention and scheduler preemption — and that each must be addressed independently.

### Workload

A deterministic CPU-bound stressor (`prime.c`) counts all primes up to 25,000,000 using trial division. No I/O, no syscalls, fixed runtime per run. Six concurrent processes compete on constrained cores to force measurable scheduler pressure.

### Configurations

| Config | Setup | What it isolates |
|--------|-------|-----------------|
| **SB** | All 6 processes pinned to 1 core (`cpu7`) | Worst-case: maximum contention + preemption |
| **C1** | 6 processes distributed across 2 cores (`cpu5`, `cpu7`) | Hardware fix: affinity reduces core starvation |
| **C2** | C1 placement + `SCHED_RR` (priority 99) on foreground process | OS fix: real-time scheduling eliminates preemption |

### Results (averaged over 10 runs)

| Config | Wall Time | vs SB | Context Switches | vs SB |
|--------|-----------|-------|-----------------|-------|
| SB | 43.72s | — | 2,470 | — |
| C1 | 22.29s | **−49.0%** | 2,449 | −0.9% (unchanged) |
| C2 | 8.46s | **−80.7%** | 24 | **−99.0%** |

**Key insight:** Affinity alone halves execution time but does not touch context switches. `SCHED_RR` alone would not recover the time lost to core starvation. Both fixes are needed, and they target different layers of the Linux stack.

Statistical validation via Welch's t-test: all comparisons `p < 0.001`, Cohen's d ranging from 1.56 (affinity on context switches — correctly small, confirming orthogonality) to 156.62 (scheduler on context switches).

### Tuning Commands

```bash
# C1: distribute across 2 P-cores
taskset -c 5,7 ./prime   # for each background worker

# C2: real-time scheduling on the foreground process
sudo chrt -r 99 taskset -c 5,7 ./prime
```

---

## Memory Tuning

**Goal:** Demonstrate that kernel memory parameter tuning (swappiness, dirty write-back thresholds, cache pressure, and Transparent Huge Pages) can significantly reduce memory pressure and improve throughput under sustained oversubscription.

### Workload

`stress-ng` with 4 workers allocating **10 GB total on an 8 GB RAM system**, forcing real swap activity throughout. Two workload types tested:

| Workload | Pattern | Simulates |
|----------|---------|-----------|
| `alloc` | `--vm`, `walk-1d` sequential | JVM heap, malloc-heavy apps |
| `cache` | `--cache`, `walk-1d` sequential | Database buffer pool, file servers |

Each run lasted 90 seconds and was repeated **5 times**; results are averaged.

### Bad Baseline Config

| Parameter | Bad Value | Why It's Bad |
|-----------|----------|-------------|
| `vm.swappiness` | 200 | Aggressively evicts anonymous pages even when RAM is available |
| `vm.vfs_cache_pressure` | 500 | Forces premature page cache eviction |
| `vm.dirty_ratio` | 5 | Flushes dirty pages too eagerly, causing write stalls |
| `vm.dirty_background_ratio` | 2 | Background flusher too aggressive |
| `vm.min_free_kbytes` | 16384 | Too low; delays background reclaim, causing sudden stalls |
| THP | `never` | Disables huge pages, increasing TLB pressure |

### Tuning Logic

Workload type is detected from swap rate and major page fault frequency:

- `avg_si_kBps + avg_so_kBps > 20` AND `avg_pgmajfault > 50` → **mixed**
- Swap-dominant → **swap-heavy**; fault-dominant → **fault-heavy**

Tuned parameters for all workloads: `swappiness=10`, `dirty_ratio=20`, `dirty_background_ratio=10`, `min_free_kbytes=262144`. Workload-specific: `vfs_cache_pressure=50` (fault-heavy) or `100` (swap-heavy); THP `always` (swap-heavy) or `madvise` (fault-heavy/mixed).

### Results (averaged over 5 iterations)

| Workload | Throughput | Page Faults/s | CPU iowait | Pressure Score |
|----------|------------|--------------|------------|---------------|
| **Alloc** | **+16.7%** | **−92.7%** | **−12.4%** | **−49.9%** |
| **Cache** | **+24.2%** | **−92.1%** | **−38.9%** | **−73.7%** |

### Tuning Commands

```bash
sudo sysctl -w vm.swappiness=10
sudo sysctl -w vm.dirty_ratio=20
sudo sysctl -w vm.dirty_background_ratio=10
sudo sysctl -w vm.min_free_kbytes=262144
sudo sysctl -w vm.vfs_cache_pressure=50          # for fault-heavy (cache) workload
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled   # for alloc
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled  # for cache/mix
```

### Running the Experiment

```bash
cd Memory/
chmod +x *.sh

./run_experiment.sh alloc   # apply tuning when prompted, press ENTER
rm -rf run_before run_after

./run_experiment.sh cache
rm -rf run_before run_after

./run_experiment.sh mix
```

---

## Disk I/O Tuning

**Goal:** Demonstrate that I/O scheduler and read-ahead tuning produce measurable improvements in IOPS, throughput, average latency, and tail latency across random, sequential, and mixed workloads.

### Workload

`fio` with `direct=1` (bypass page cache) and `libaio` engine against a 4 GB test file. Caches are flushed between runs.

| Workload | fio Mode | Block Size | Jobs | I/O Depth | Duration |
|----------|----------|-----------|------|-----------|---------|
| `rand` | `randread` | 4 KB | 4 | 64 | 90s |
| `seq` | `read` | 1 MB | 2 | 64 | 90s |
| `mix` | `randrw` (70R/30W) | 4 KB | 4 | 64 | 90s |

### Bad Baseline Configs

| Workload | Bad Config | Why It's Bad |
|----------|-----------|-------------|
| `rand` | `none` scheduler + RA 1024 | No request reordering + wasteful prefetch for 4K random I/O |
| `seq` | `none` scheduler + RA 32 | No reordering + starved prefetch pipeline for 1M sequential reads |
| `mix` | `none` scheduler + RA 4096 | No read/write fairness + massive wasted prefetch for 4K mixed I/O |

### Tuning Logic

```
write_ratio > 0.15              → mixed workload
avg_req_size > 128 KB           → sequential workload
avg_req_size < 32 KB            → random workload

avg_queue > 50                  → use mq-deadline
Otherwise                       → use none

Sequential  → read-ahead 1024
Mixed       → read-ahead 512
Random      → read-ahead 128
```

### Results

| Workload | IOPS | Bandwidth | Avg Latency | P99.9 Latency | PSI Pressure |
|----------|------|-----------|-------------|--------------|-------------|
| **Random** | +36.8% | +36.3% | −25.3% | **−84.3%** | −67.2% |
| **Sequential** | +66.7% | +66.7% | −39.1% | **−92.7%** | −63.2% |
| **Mixed** | +18.0% (R) / +18.3% (W) | +18.0% | −6.8% (R) / −31.6% (W) | **−83.3% (R) / −78.5% (W)** | −50.0% |

**Note on Sequential P50 latency:** P50 rose slightly (+47.8%) even as average and tail latency improved substantially. The baseline had a bimodal distribution (fast median, catastrophic tail). Tuning eliminated the stalls, producing a tight unimodal distribution centered ~167ms. Std dev dropped 93%.

### Tuning Commands

```bash
# Random workload
echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler
sudo blockdev --setra 128 /dev/sda

# Sequential workload
echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler
sudo blockdev --setra 1024 /dev/sda

# Mixed workload
echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler
sudo blockdev --setra 512 /dev/sda
```

### Running the Experiment

```bash
cd Disk/
chmod +x *.sh

./run_experiment.sh rand    # apply tuning when prompted, press ENTER
rm -rf run_before run_after

./run_experiment.sh seq
rm -rf run_before run_after

./run_experiment.sh mix
```

> **Important:** Always run `rm -rf run_before run_after` between experiments to prevent mixing data across workload types. Plots are saved to workload-specific directories (`comparison_plots_ran/`, `comparison_plots_seq/`, `comparison_plots_mix/`) and will not be overwritten.

---

## Results Summary

| Subsystem | Workload | Key Improvement |
|-----------|----------|----------------|
| **CPU** | Affinity (SB → C1) | −49.0% execution time |
| **CPU** | Scheduler (C1 → C2) | −99.0% context switches, −80.7% total wall time vs SB |
| **Memory** | Alloc | +16.7% throughput, −92.7% page faults |
| **Memory** | Cache | +24.2% throughput, −92.1% page faults |
| **Disk** | Random | +36.8% IOPS, −84.3% P99.9 latency |
| **Disk** | Sequential | +66.7% IOPS, −92.7% P99.9 latency |
| **Disk** | Mixed | +18.0% IOPS, −83.3% P99.9 read latency |

### Key Takeaways

1. **Bottlenecks are subsystem-specific.** Fixing CPU contention does not help memory or disk. Each subsystem must be tuned independently with workload-appropriate parameters.

2. **Tail latency is where tuning matters most.** Median/average improvements ranged from 7–39% across disk workloads; P99.9 improvements were 78–93%. The tuning eliminates catastrophic stalls, not just averages.

3. **Workload classification is critical.** Mixed disk workloads must be detected via `write_ratio`, not just request size. Random memory access defeats the kernel's LRU prediction; sequential access (`walk-1d`) is necessary for swappiness tuning to be effective.

4. **Some metrics are misleading.** With low swappiness, pages are retained until memory is exhausted and evicted in large bursts — raising the *average* swap-out rate even though performance improves. `avg_pgmajfault` and `iowait` are the reliable indicators, not `avg_so_kBps` or `avg_free_mb`.

5. **PSI is a reliable health indicator.** Pressure Stall Information dropped 50–67% across all disk workloads and consistently reflected real improvement even when individual fio metrics showed mixed signals.

6. **Affinity and scheduling are orthogonal.** CPU affinity fixes hardware-level resource allocation (−0.9% on context switches). `SCHED_RR` fixes OS-level preemption behavior (−99.0% on context switches). Both are needed for full optimization and they do not substitute for each other.

---

## Prerequisites

### CPU Experiment
- Physical Linux machine with multiple cores
- `perf` (`sudo apt install linux-tools-common linux-tools-generic`)
- `chrt`, `taskset` (part of `util-linux`)
- Python 3 with `matplotlib`, `scipy` (`pip3 install matplotlib scipy`)

### Memory Experiment
- Linux VM with at least 8 GB RAM
- Root/sudo access
- `stress-ng` (`sudo apt install stress-ng`)
- `sysstat` (`sudo apt install sysstat`)
- A swap partition or swap file (≥2 GB):
  ```bash
  sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile && sudo swapon /swapfile
  ```
- Python 3 with `pandas`, `matplotlib`, `scipy`, `numpy`

### Disk Experiment
- Linux VM with disk device `sda` (~5 GB free space for 4 GB test file)
- Root/sudo access
- `fio` (`sudo apt install fio`)
- `sysstat` (`sudo apt install sysstat`)
- Python 3 with `pandas`, `matplotlib`
