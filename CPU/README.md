# CPU Performance Tuning — Controlled Experiment System

**Platform:** Intel Core Ultra 5 125H · Ubuntu · Kernel 7.0.0-14-generic  
**Method:** Controlled multi-run experiment with statistical validation  
**Tools:** `taskset`, `chrt`, `perf stat`, `/usr/bin/time`, Welch's t-test  

---

## What This Project Is

This is **not** a generic monitoring tool.  
It is a two-phase controlled experiment system that:

1. **Detects** system conditions and suggests CPU tunings based on observed metrics
2. **Proves** empirically — under strict controlled conditions — whether a suggested tuning actually improves performance, and by how much

The distinction matters. Most performance tuning claims are anecdotal. This system produces statistically validated evidence with explicit scope boundaries.

---

## Project Structure

```
CPU/
├── workload/
│   ├── prime.c              ← CPU-bound stressor (pthreads, deterministic)
│   ├── build.sh             ← Compile prime.c
│   └── prime                ← Compiled binary (generated after build)
├── scripts/
│   ├── detect_pcores.sh     ← Identifies P-cores by max frequency (hybrid CPU safe)
│   ├── measure.sh           ← Shared measurement helpers (sourced, not run directly)
│   ├── run_baseline.sh      ← State A (clean) + State B (contention) collection
│   ├── run_tuned.sh         ← State C1 (affinity split) + C2 (affinity + RT) collection
│   └── compare.sh           ← Statistical analysis + final_report.txt generation
├── results/
│   ├── environment.txt      ← Hardware + kernel snapshot at time of experiment
│   ├── state_A.csv          ← Clean baseline measurements
│   ← state_B.csv          ← Synthetic contention measurements
│   ├── state_C1.csv         ← Tuning 1 measurements
│   ├── state_C2.csv         ← Tuning 2 measurements
│   └── final_report.txt     ← Full statistical report
└── README.md
```

---

## Experiment Design

### The Four States

| State | Configuration | Purpose |
|-------|--------------|---------|
| A | Single process, both P-cores, no competition | Sanity check — true system baseline |
| B | Two processes competing on same CPU set | The manufactured problem |
| C1 | Two processes, each pinned to a dedicated P-core | Tuning 1: CPU affinity split |
| C2 | Affinity split + FIFO real-time scheduling (chrt -f 99) | Tuning 2: isolates preemption cost |

The key comparison is **B → C1 → C2**, not A → C. State A is a reference point, not the baseline for improvement calculations. The problem we are solving is State B — synthetic contention — and all tuning claims are made relative to it.

### Why Only Two Metrics

| Metric | Tool | Role |
|--------|------|------|
| Wall-clock execution time | `/usr/bin/time -f "%e"` | Primary — did the work finish faster? |
| CPU migrations | `perf stat -e cpu-migrations` | Mechanistic — explains *why* time changed |

Intentionally excluded: CPU utilization, context switches, cache hit rates, IPC. These are correlated signals, not causal ones for this experiment. Using them would obscure the specific claim being tested.

### Hybrid CPU Handling

This experiment runs on an Intel hybrid architecture (P-cores + E-cores + LP-cores). Naive use of `taskset -c 0,1` risks landing threads on cores running at different clock speeds (4500 MHz vs 3600 MHz vs 2500 MHz), silently invalidating comparisons.

`detect_pcores.sh` reads `/sys/devices/system/cpu/cpuN/cpufreq/cpuinfo_max_freq` for every logical CPU, ranks by maximum frequency, and selects two cores from different physical cores (verified via `thread_siblings_list`) at the same peak frequency. All experiments run exclusively on identified P-cores.

### Statistical Validation

Each state is measured **15 independent runs** with a 3-second cooldown between runs. Results are analyzed using:

- Mean, standard deviation, standard error
- Min/max range
- Welch's t-test (does not assume equal variance) between B vs C1, B vs C2, and C1 vs C2
- Significance threshold: |t| > 2 (approximates α = 0.05 for df > 14)

---

## Experimental Results

Three complete experimental runs were conducted. Results across runs reveal a hardware-dependent finding.

### Run 1 — powersave governor, UPPER_LIMIT = 5M

| State | Mean Wall Time | Migrations |
|-------|---------------|------------|
| A | 1.790s | 4.80 |
| B | 2.513s | 3.53 |
| C1 | 1.823s | 1.00 |

**B → C1: +27.45% wall-time improvement, t = 41.93 (SIGNIFICANT)**  
Migration reduction: 71.70%

### Run 2 — performance governor, UPPER_LIMIT = 5M, P-cores locked

| State | Mean Wall Time | Migrations |
|-------|---------------|------------|
| A | 0.799s | 1.60 |
| B | 1.897s | 2.33 |
| C1 | 1.543s | 1.00 |

**B → C1: +18.66% wall-time improvement, t = 4.59 (SIGNIFICANT)**  
Migration reduction: 57.14%

### Run 3 — performance governor, UPPER_LIMIT = 25M, P-cores locked

| State | Mean Wall Time | Migrations |
|-------|---------------|------------|
| A | 7.296s | 1.80 |
| B | 14.460s | 31.47 |
| C1 | 14.475s | 1.00 |
| C2 | 14.481s | 0.00 |

**B → C1: -0.10% wall-time change, t = -1.33 (NOT significant)**  
Migration reduction: 96.82%  
**B → C2: -0.15% wall-time change, t = -1.62 (NOT significant)**  
Migration reduction: 100.00%

---

## Key Finding

Migration count and wall-clock time are **not reliably correlated** on modern Intel hybrid CPUs with large shared L3 caches.

In Run 3, CPU migrations dropped by 96.82% — from 31.47 to 1.00 — with zero measurable wall-time improvement. The explanation is architectural: cpu5 and cpu7 are both P-cores sharing a 12MB L3 cache. When a thread migrates between them, its working set (prime sieve up to 25M integers) remains resident in the shared L3. The migration cost is an L3 hit (~30 cycles at 4.5 GHz ≈ 7ns) rather than a RAM reload (~300 cycles). Across 31 migrations, total migration overhead is approximately 200ns — invisible against a 14.46s runtime.

In Run 1, the same tuning produced 27.45% improvement because the `powersave` governor introduced frequency instability between runs, compounding scheduling overhead with thermal throttling effects. Affinity pinning eliminated both simultaneously.

**The wall-time benefit of CPU affinity partitioning on this hardware is governor-dependent, not migration-count-dependent.**

---

## Claims

### What This Experiment Proves

Under `powersave` governor conditions on an Intel Core Ultra 5 125H:
> CPU affinity partitioning reduces wall-clock execution time by 27.45% (t=41.93) and CPU migrations by 71.7% when two competing CPU-bound processes are pinned to dedicated P-cores instead of sharing a CPU set, across 15 controlled runs.

Under `performance` governor with P-core pinning:
> CPU affinity partitioning consistently eliminates CPU migrations (96-100% reduction) but produces no statistically significant wall-time improvement, because same-tier P-core migrations are absorbed by the shared L3 cache on this architecture.

### What This Does NOT Prove

- That these results generalize to other CPU architectures, cache topologies, or workload types
- That migration count alone predicts performance degradation
- That affinity tuning is always beneficial or always neutral
- Any claim about NUMA systems, multi-socket machines, or E-core workloads

---

## How to Reproduce

### Prerequisites

```bash
sudo apt update
sudo apt install linux-tools-common linux-tools-generic linux-tools-$(uname -r) python3 time
```

For RT scheduling (State C2), add RT priority limits:

```bash
sudo mkdir -p /etc/systemd/system/user@.service.d/
sudo tee /etc/systemd/system/user@.service.d/rtprio.conf << EOF
[Service]
LimitRTPRIO=99