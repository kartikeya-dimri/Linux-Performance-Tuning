# CPU Performance Tuning — Linux Scheduler & Affinity Experiment

> **Course:** Linux Performance Tuning (Sem 6)  
> **Objective:** Demonstrate two independent, measurable CPU performance improvements under controlled stress conditions using CPU affinity and real-time scheduler tuning.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Background & Motivation](#background--motivation)
3. [Workload Design](#workload-design)
4. [Experiment Design](#experiment-design)
5. [Implementation](#implementation)
6. [How to Run](#how-to-run)
7. [Results](#results)
8. [Interpretation & Analysis](#interpretation--analysis)
9. [Statistical Validation](#statistical-validation)
10. [Key Takeaways](#key-takeaways)
11. [Limitations & Honest Notes](#limitations--honest-notes)

---

## Project Structure

```
CPU_Tuning/
├── workload/
│   ├── prime.c          # CPU-bound stressor (deterministic prime sieve)
│   ├── prime            # compiled binary (after build)
│   └── build.sh         # compile script
├── scripts/
│   ├── common.sh        # shared config + measure_run() helper
│   ├── detect_pcores.sh # auto-detect P-cores on hybrid Intel CPUs
│   ├── run_baselines.sh # collect SB (contention baseline)
│   ├── run_experiments.sh # collect C1 (affinity) and C2 (scheduler)
│   └── analyze.sh       # stats, plots, final report
├── results/
│   ├── raw/             # SB.csv, C1.csv, C2.csv
│   └── plots/           # 6 PNG plots
└── docs/
    ├── environment.txt  # system snapshot at time of run
    └── final_report.txt # generated stats report
```

---

## Background & Motivation

### The Problem

On a modern Linux system, multiple processes competing for the same CPU core cause two distinct performance penalties:

1. **Core contention** — the OS must time-share the core across all runnable processes, so each one gets only a fraction of the available compute time.
2. **Scheduler preemption** — the OS involuntarily interrupts a running process (context switch) to give another process CPU time. Each context switch wastes cycles saving/restoring state and pollutes CPU caches.

These are **two orthogonal problems** requiring different fixes:
- Core contention → fix with **CPU affinity** (hardware-level tuning)
- Scheduler preemption → fix with **scheduling policy** (OS-level tuning)

This experiment isolates and demonstrates both effects independently, with statistical validation.

### Why the First Design Failed

An earlier version of this experiment used only 2 processes. With 2 processes on 2 cores, context switch counts were near-zero (single digits per run), so scheduler tuning showed no measurable impact. The fix: increase to **6 competing processes on constrained cores**, which forces the scheduler into aggressive time-sharing and generates thousands of context switches in the baseline — giving scheduler tuning something meaningful to improve.

---

## Workload Design

### `prime.c` — Deterministic CPU-Bound Stressor

Each process independently counts all prime numbers up to 25,000,000 using trial division.

**Why this workload:**
- **Purely CPU-bound** — no I/O, no sleep, no syscalls during computation
- **Deterministic** — same input always produces the same runtime (±noise from scheduling)
- **Scalable** — can run N independent instances to create N-way contention
- **Self-timing** — reports wall time via `CLOCK_MONOTONIC`

```c
#define UPPER_LIMIT 25000000UL   // fixed problem size → fixed work per process

static int is_prime(unsigned long n) { ... }  // trial division

static void *compute_primes(void *arg) {
    for (unsigned long n = 2; n <= UPPER_LIMIT; n++)
        if (is_prime(n)) count++;
    ...
}
```

**Single-process baseline:** ~14 seconds on a P-core (cpu7).

---

## Experiment Design

### Parameters

| Parameter | Value | Rationale |
|---|---|---|
| Processes per run | 6 | Creates heavy scheduler pressure (forces thousands of ctx switches) |
| Cores available | 2 (cpu5, cpu7) | Constrained resource pool; 6 processes on 2 cores = 3× oversubscription |
| Runs per condition | 10 | Enough for Welch's t-test; balances time vs statistical power |
| Cooldown between runs | 5s | Lets CPU thermal state and scheduler state settle |
| Metric 1 | Wall time (seconds) | Primary: total execution time of the measured foreground process |
| Metric 2 | Context switches | Secondary: involuntary preemptions measured by `perf stat` |

### Three Conditions

#### SB — Stress Baseline (Worst Case)

All 6 processes pinned to a **single core** (`cpu7`) using `taskset`.

```
cpu7: [P1] [P2] [P3] [P4] [P5] [P6]   ← all 6 fighting for 1 core
cpu5: (idle)
```

- The OS must round-robin 6 processes on 1 core
- Each process gets ~1/6 of the available CPU time
- Context switches are in the **thousands** per run
- This is the controlled worst-case, not a normal workload

#### C1 — CPU Affinity Tuning

All 6 processes spread across **two cores** (`cpu5,7`) using `taskset`.

```
cpu7: [P1] [P2] [P3]   ← 3 processes
cpu5: [P4] [P5] [P6]   ← 3 processes
```

- Each process still shares a core with 2 others, but only fights 2 competitors instead of 5
- The OS context-switches less (fewer competing processes per core)
- Expected: **execution time ↓ ~50%**, context switches ↓ moderately
- Only change from SB: **core assignment** — same processes, same workload, same scheduler

#### C2 — Affinity + Real-Time Scheduler Tuning

Same 2-core spread as C1, but the foreground (measured) process runs under `SCHED_RR` at priority 99 via `chrt -r 99`. Background workers run at `chrt -r 98`.

```
cpu7/cpu5: [P1(RR-99)] vs [P2(RR-98)] [P3(RR-98)] ...
```

- `SCHED_RR` (Round-Robin real-time) is a **higher scheduling class** than `SCHED_OTHER` (the normal Linux scheduler)
- Real-time processes **preempt** normal processes immediately and are only preempted by equal/higher real-time processes
- Since background workers run at RR-98 (one step below the foreground), the foreground process is almost never involuntarily preempted
- Expected: **context switches ↓ dramatically**, execution time ↓ further
- Only change from C1: **scheduling policy** — same cores, same processes, same workload

### Measurement Method

For each run, `measure_run()` in `common.sh`:
1. Launches `PROCS-1` (5) background workers in the background
2. Runs 1 foreground process wrapped in `perf stat -e context-switches` and `/usr/bin/time -f "%e"`
3. Waits for background workers to finish
4. Parses wall time and context switch count
5. Appends `run,wall_sec,context_switches` to the condition's CSV

```bash
# Foreground measurement (C2 example)
/usr/bin/time -f "%e" -o "$tmp_time" \
perf stat -e context-switches -o "$tmp_perf" -- \
taskset -c "$fg_cores" chrt -r 99 "$WORKLOAD" 1
```

---

## Implementation

### `common.sh` — Core Configuration

```bash
RUNS=10          # iterations per condition
PROCS=6          # total competing processes per run
WAIT=5           # cooldown seconds

CORE_SB="7"      # SB: all on one core
CORES_C1="5,7"   # C1: spread across two cores
CORES_C2="5,7"   # C2: same spread + real-time scheduling
```

### `run_baselines.sh` — Collect SB

Runs `RUNS` iterations of: 5 background workers + 1 measured foreground, all on `cpu7`.

### `run_experiments.sh` — Collect C1 and C2

**C1:** Same multi-process launch, spread across `cpu5,7`, `SCHED_OTHER` (normal).

**C2:** Same as C1, but:
- Foreground: `chrt -r 99` (SCHED_RR, priority 99)
- Background workers: `chrt -r 98` (SCHED_RR, priority 98)
- Requires `sudo` or `CAP_SYS_NICE` capability

### `analyze.sh` — Statistics and Plots

- Loads `SB.csv`, `C1.csv`, `C2.csv`
- Computes mean, SD, SE per condition per metric
- Runs **Welch's t-test** (unequal variance) for SB vs C1 and C1 vs C2
- Computes **Cohen's d** (effect size) for each comparison
- Generates 6 plots (bar, box, KDE) for both metrics
- Writes `final_report.txt`

---

## How to Run

### Prerequisites

```bash
sudo apt install gcc linux-tools-common linux-tools-$(uname -r) util-linux
# util-linux provides chrt; linux-tools provides perf
```

### Step 1 — Build

```bash
bash workload/build.sh
# Compiles prime.c → workload/prime
# Runs a sanity test on cpu7 (~14s)
```

### Step 2 — Collect Baseline

```bash
bash scripts/run_baselines.sh
# Produces results/raw/SB.csv
```

### Step 3 — Run Experiments

```bash
sudo bash scripts/run_experiments.sh
# Produces results/raw/C1.csv and C2.csv
# sudo required for chrt -r (SCHED_RR)
```

### Step 4 — Analyze

```bash
bash scripts/analyze.sh
# Produces results/plots/*.png and docs/final_report.txt
```

### Estimated Total Time

| Step | Time |
|---|---|
| Build + sanity | ~15s |
| SB (10 runs × ~44s + 5s cooldown) | ~8 min |
| C1 (10 runs × ~22s + 5s cooldown) | ~5 min |
| C2 (10 runs × ~8s + 5s cooldown) | ~2.5 min |
| Analysis | ~10s |
| **Total** | **~16 minutes** |

---

## Results

### Execution Time

| Condition | Mean (s) | SD (s) | Change vs SB |
|---|---|---|---|
| SB | 43.720 | 0.018 | — |
| C1 | 22.288 | 0.992 | **−49.0%** |
| C2 | 8.455 | 0.838 | **−80.7%** |

### Context Switches

| Condition | Mean | SD | Change vs SB |
|---|---|---|---|
| SB | 2470 | 5 | — |
| C1 | 2449 | 19 | −0.9% |
| C2 | 24 | 11 | **−99.0%** |

### Statistical Tests (Welch's t-test)

| Comparison | Metric | t | p-value | Cohen's d | Significant? |
|---|---|---|---|---|---|
| SB vs C1 | Wall time | 68.34 | < 0.001 | 30.56 | ✓ YES |
| C1 vs C2 | Wall time | 33.69 | < 0.001 | 15.07 | ✓ YES |
| SB vs C1 | Ctx switches | 3.49 | 0.006 | 1.56 | ✓ YES |
| C1 vs C2 | Ctx switches | 350.22 | < 0.001 | 156.62 | ✓ YES |

---

## Interpretation & Analysis

### SB → C1: Affinity Tuning (Hardware-Level)

Spreading 6 processes from 1 core to 2 cores cut execution time by **49%** — essentially halving it, exactly as the resource model predicts. When all 6 processes share 1 core, each gets ~1/6 of the available compute time. With 2 cores, each gets ~1/3. The measured process finishes twice as fast.

Context switches dropped only **0.9%** (2470 → 2449). This is expected: `SCHED_OTHER` still round-robins fairly across all processes on each core, so even with 3 processes per core instead of 6, there is still frequent preemption. Affinity solves the **resource** problem, not the **preemption** problem.

**What affinity does:** Gives each process more CPU time by reducing how many competitors it shares a core with. It does not change how the scheduler behaves toward each process.

### C1 → C2: Scheduler Tuning (OS-Level)

Promoting the foreground process to `SCHED_RR` (priority 99) caused context switches to drop **99%** (2449 → 24) and execution time to drop a further **62%** (22.3s → 8.5s).

`SCHED_RR` belongs to the **real-time scheduling class**, which is fundamentally different from `SCHED_OTHER`:
- A `SCHED_RR` process at priority 99 **preempts** all `SCHED_OTHER` processes immediately
- It only yields when: (a) its time quantum expires and another equal-priority RR process is waiting, or (b) it blocks on I/O (which never happens in our CPU-bound workload)
- Background workers at priority 98 can preempt each other, but **not** the priority-99 foreground process

The result: the foreground process runs almost uninterrupted (only 24 context switches vs 2449), which both explains the near-zero context switch count and the dramatic speed improvement.

**The time improvement is larger than context switch reduction alone would predict.** This is because with `SCHED_RR`, the foreground process also **monopolises** its core — it does not yield to the priority-98 background workers at all (only to other priority-99 processes, of which there are none). So the time improvement comes from two combined effects: fewer context switches and higher CPU monopolisation.

### The Two Dimensions Are Independent

This is the core finding of the experiment:

```
                    Context Switches    Execution Time
SB  (1 core, normal)    HIGH                SLOW
C1  (2 cores, normal)   HIGH                FASTER    ← affinity fixes time, not ctx
C2  (2 cores, realtime) LOW                 FASTEST   ← scheduler fixes ctx (and time)
```

**CPU affinity** solves the hardware resource problem: more cores = more parallel compute = less waiting.

**Scheduler policy** solves the preemption problem: higher scheduling class = fewer involuntary interruptions = smoother, faster execution.

A system suffering from both problems benefits from both fixes. They are not alternatives — they are complementary.

---

## Statistical Validation

### Why Welch's t-test (not Student's t-test)?

Welch's t-test does not assume equal variance between groups. Inspecting the SDs confirms this was the right choice:
- SB wall time SD = 0.018s (extremely consistent — fully saturated core has no randomness)
- C1 wall time SD = 0.992s (more variable — contention on 2 cores has more OS scheduling noise)

Equal-variance t-test would be incorrect here.

### Why Cohen's d matters

p-values only tell you whether an effect is real; they don't tell you how large it is. With 10 runs each, even tiny differences can be significant. Cohen's d normalises the effect size:

| d value | Interpretation |
|---|---|
| 0.2 | Small |
| 0.5 | Medium |
| 0.8 | Large |
| > 2 | Very large |

Our smallest effect (SB vs C1 context switches, d = 1.56) is still nearly twice the "large" threshold. The largest (C1 vs C2 context switches, d = 156.62) indicates the two distributions have essentially zero overlap — a definitive result.

### Distribution Plots

The 6 generated plots show:
- **Bar charts** (mean ± SE): quick visual comparison of central tendency
- **Box plots** (IQR + whiskers): show spread, median, and outliers
- **KDE density curves**: show full shape of each distribution — confirm normality and separation

For C1 vs C2 context switches, the KDE curves do not overlap at all — C1 is centred around 2449 and C2 around 24. This is visually striking and supports the statistical result.

---

## Key Takeaways

1. **CPU affinity is a hardware-level fix.** Pinning processes to separate cores eliminates forced time-sharing and directly reduces execution time proportional to the reduction in competition.

2. **Scheduler tuning is an OS-level fix.** `SCHED_RR` (real-time) eliminates involuntary preemption of the measured process, collapsing context switches by 99% and further improving execution time.

3. **The two tunings are orthogonal.** Affinity does not reduce context switches. Scheduler tuning does not replace the need for adequate cores. Both are needed for full optimisation.

4. **Contention must be high enough for scheduler tuning to show.** With only 2 processes, context switch counts are near-zero and scheduler tuning has nothing to improve. The redesign (6 processes, constrained cores) was essential to making C2 measurable.

5. **Real-time scheduling (`SCHED_RR`) requires elevated privileges.** `chrt -r` requires `sudo` or `CAP_SYS_NICE`. `nice` is not a substitute — it only adjusts weight within `SCHED_OTHER`, not scheduling class.

---

## Limitations & Honest Notes

- **Results reflect controlled stress conditions.** 6 competing CPU-bound processes on 2 cores is an artificially hostile environment. In normal workloads, contention is lower and gains would be smaller.

- **C2's execution time improvement is partly from monopolisation.** With SCHED_RR at priority 99, the foreground process does not yield to background workers at all — so its speed gain is not purely from fewer context switches, but also from capturing more CPU time. This is real SCHED_RR behaviour, but worth being explicit about.

- **`SCHED_RR` is not appropriate for general-purpose workloads.** Real-time scheduling can starve normal processes. It is useful for latency-sensitive applications (audio, robotics, HPC), not as a general performance trick.

- **Single machine, single run session.** Results may vary across different CPU microarchitectures, kernel versions, or system load levels. The relative ordering of SB < C1 < C2 for execution time is expected to hold; absolute values will differ.

- **Context switches measured for foreground process only.** Background worker context switches are not reported — only the measured foreground process is instrumented by `perf stat`.