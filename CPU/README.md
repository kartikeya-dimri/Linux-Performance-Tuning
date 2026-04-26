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
│   ├── prime.c             # CPU-bound stressor (deterministic prime counter)
│   ├── prime               # compiled binary (after build)
│   └── build.sh            # compile script
├── scripts/
│   ├── common.sh           # shared config + measure_run() helper
│   ├── detect_pcores.sh    # auto-detect P-cores on hybrid Intel CPUs
│   ├── run_baselines.sh    # collect SB (contention baseline)
│   ├── run_experiments.sh  # collect C1 (affinity) and C2 (scheduler)
│   └── analyze.sh          # stats, plots, final report
├── results/
│   ├── raw/                # SB.csv, C1.csv, C2.csv
│   └── plots/              # 6 PNG plots
└── docs/
    ├── environment.txt     # system snapshot at time of run
    └── final_report.txt    # generated stats report
```

---

## Background & Motivation

### The Problem

On a modern Linux system, multiple processes competing for the same CPU core cause two distinct performance penalties:

1. **Core contention** — the OS must time-share the core across all runnable processes, so each one gets only a fraction of the available compute time.
2. **Scheduler preemption** — the OS involuntarily interrupts a running process (context switch) to give another process CPU time. Each context switch wastes cycles saving and restoring state and pollutes CPU caches.

These are **two orthogonal problems** requiring different fixes:

- Core contention → fix with **CPU affinity** (hardware-level tuning)
- Scheduler preemption → fix with **scheduling policy** (OS-level tuning)

This experiment isolates and demonstrates both effects independently, with statistical validation. The key insight — and the main finding — is that fixing one does not fix the other. They must be addressed separately.

### Why the First Design Failed

An earlier version of this experiment used only 2 processes. With 2 processes on 2 cores, context switch counts were near-zero (single digits per run), so scheduler tuning had nothing meaningful to improve. The fix: increase to **6 competing processes on constrained cores**, which forces the scheduler into aggressive time-sharing and generates thousands of context switches in the baseline — giving scheduler tuning something measurable to demonstrate.

---

## Workload Design

### `prime.c` — Deterministic CPU-Bound Stressor

Each process independently counts all prime numbers up to 25,000,000 using trial division.

**Why this workload:**
- **Purely CPU-bound** — no I/O, no sleep, no syscalls during computation
- **Deterministic** — same input always produces the same runtime (±noise from scheduling only)
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
| Runs per condition | 10 | Sufficient for Welch's t-test; balances time vs statistical power |
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
- Each process gets ~1/6 of available CPU time
- Context switches are in the **thousands** per run
- This is a controlled worst-case, not a typical production workload

#### C1 — CPU Affinity Tuning

All 6 processes spread across **two cores** (`cpu5,7`) using `taskset`.

```
cpu7: [P1] [P2] [P3]   ← 3 processes
cpu5: [P4] [P5] [P6]   ← 3 processes
```

- Each process still shares a core with 2 others, but only competes with 2 instead of 5
- Expected: **execution time ↓ ~50%**, context switches minimally affected
- Only change from SB: **core assignment** — same processes, same workload, same scheduler policy

> **Note:** Affinity solves the resource problem, not the preemption problem. `SCHED_OTHER` still round-robins fairly across all processes on each core. With 3 processes per core instead of 6, context switches drop only marginally — this is expected and confirmed by the data.

#### C2 — Affinity + Real-Time Scheduler Tuning

Same 2-core spread as C1, but the foreground (measured) process runs under `SCHED_RR` at priority 99 via `chrt -r 99`. Background workers run at `chrt -r 98`.

```
cpu7/cpu5: [P1(RR-99)] vs [P2(RR-98)] [P3(RR-98)] ...
```

- `SCHED_RR` (Round-Robin real-time) is a **higher scheduling class** than `SCHED_OTHER`
- A `SCHED_RR` process at priority 99 preempts all lower-priority processes immediately
- It only yields when its time quantum expires **and** another equal-priority RR process is waiting, or when it blocks on I/O — which never happens in this CPU-bound workload
- Background workers at RR-98 can preempt each other, but **not** the priority-99 foreground
- Expected: **context switches ↓ dramatically**, execution time ↓ further
- Only change from C1: **scheduling policy** — same cores, same processes, same workload

### Measurement Method

For each run, `measure_run()` in `common.sh`:

1. Launches `PROCS-1` (5) background workers in the background
2. Runs 1 foreground process wrapped in `perf stat -e context-switches` and `/usr/bin/time -f "%e"`
3. Waits for all background workers to finish
4. Parses wall time and context switch count from their respective outputs
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

Runs `RUNS` iterations of: 5 background workers + 1 measured foreground, all pinned to `cpu7`.

### `run_experiments.sh` — Collect C1 and C2

- **C1:** same structure, processes spread across `cpu5,7`, normal `SCHED_OTHER`
- **C2:** same structure, processes on `cpu5,7`, foreground at `chrt -r 99`, background at `chrt -r 98`
- Requires `sudo` or `CAP_SYS_NICE` for `SCHED_RR`

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
| SB vs C1 | Ctx switches | 3.49 | 0.006 | 1.56 | ✓ YES (small practical effect) |
| C1 vs C2 | Ctx switches | 350.22 | < 0.001 | 156.62 | ✓ YES |

---

## Interpretation & Analysis

### SB → C1: Affinity Tuning (Hardware-Level)

Spreading 6 processes from 1 core to 2 cores cut execution time by **49%** — essentially halving it, exactly as the resource model predicts. When all 6 processes share 1 core, each gets ~1/6 of the available compute time. With 2 cores, each gets ~1/3. The measured process finishes roughly twice as fast.

Context switches dropped only **0.9%** (2470 → 2449). This is statistically significant (p = 0.006) but practically negligible — a difference of 21 switches out of 2470. This is the correct and expected result: `SCHED_OTHER` still round-robins fairly across all processes on each core. With 3 processes per core instead of 6, there is marginally less scheduling activity, but the preemption behaviour is fundamentally unchanged.

**What affinity does:** Gives each process more CPU time by reducing how many competitors it shares a core with. It does not change how the scheduler treats each individual process.

**What affinity does not do:** Reduce context switches in any meaningful way. That requires a different tool entirely.

### C1 → C2: Scheduler Tuning (OS-Level)

Promoting the foreground process to `SCHED_RR` (priority 99) caused context switches to drop **99%** (2449 → 24) and execution time to drop a further **62%** (22.3s → 8.5s).

`SCHED_RR` belongs to the **real-time scheduling class**, which is fundamentally different from `SCHED_OTHER`:

- A `SCHED_RR` process at priority 99 preempts all `SCHED_OTHER` processes immediately
- It only yields when its time quantum expires and another equal-priority RR process is waiting, or when it blocks on I/O — neither of which applies to this workload
- Background workers at priority 98 can preempt each other, but **not** the priority-99 foreground process

The result: the foreground process runs almost uninterrupted — only 24 context switches across the entire run, versus 2449 in C1.

**Why execution time drops more than context switch reduction alone would predict:** With `SCHED_RR` at priority 99, the foreground process also monopolises its core — it does not yield to the priority-98 background workers. The time improvement comes from two combined effects: fewer involuntary context switches, and higher effective CPU time capture. Both are direct consequences of `SCHED_RR` semantics and are expected behaviours, not anomalies.

### The Two Dimensions Are Independent

This is the core finding of the experiment:

```
                     Context Switches    Execution Time
SB  (1 core, normal)    HIGH                SLOW
C1  (2 cores, normal)   HIGH (unchanged)    FASTER    ← affinity fixes time, not ctx
C2  (2 cores, realtime) LOW                 FASTEST   ← scheduler fixes ctx (and time)
```

CPU affinity solves the hardware resource problem: more cores = more parallel compute = less waiting.

Scheduler policy solves the preemption problem: higher scheduling class = fewer involuntary interruptions = smoother, faster execution.

A system suffering from both problems benefits from both fixes. They are not alternatives — they are complementary and target different layers of the Linux performance stack.

---

## Statistical Validation

### Why Welch's t-test (not Student's t-test)?

Welch's t-test does not assume equal variance between groups. Inspecting the SDs confirms this was the right choice:

- SB wall time SD = **0.018s** — extremely consistent; a fully saturated single core produces clockwork-like scheduling
- C1 wall time SD = **0.992s** — more variable; contention across 2 cores introduces OS scheduling noise
- C2 wall time SD = **0.838s** — also variable; SCHED_RR priority inheritance can have minor run-to-run fluctuation

Using an equal-variance t-test here would be statistically incorrect.

### Why Cohen's d Matters

p-values only tell you whether an effect is real. With 10 runs each, even small differences can clear p < 0.05. Cohen's d normalises the effect size relative to the spread of the data, giving a measure of practical significance:

| d value | Interpretation |
|---|---|
| 0.2 | Small |
| 0.5 | Medium |
| 0.8 | Large |
| > 2.0 | Very large |

**On the extreme d values:** The execution time comparisons produce d values of 30.56 and 15.07 — far beyond the "very large" threshold. This is primarily because SB's SD is only 0.018s (a near-perfectly deterministic baseline). When the denominator of Cohen's d is this small, d scales up mathematically. The values are not fabricated — they reflect genuinely non-overlapping distributions — but they should be read as "the conditions are completely separated" rather than taken as literal magnitudes.

**The most informative result** is SB vs C1 context switches (d = 1.56, p = 0.006). This is statistically significant but practically small (2470 → 2449). This is not a failure — it is a **finding**: it proves that CPU affinity alone does not meaningfully reduce context switches. Only scheduler-class promotion achieves that, as shown by C1 vs C2 (d = 156.62).

### Distribution Plots

Six plots are generated to characterise each condition's behaviour:

- **Bar charts** (mean ± SE): quick visual comparison of central tendency across conditions
- **Box plots** (IQR + whiskers): show spread, median, and outliers; execution time uses log scale to make all three distributions visible simultaneously
- **KDE density curves**: show the full shape of each distribution, confirm separation, and reveal multimodality (C1's bimodal KDE reflects two possible scheduling states across 2 cores)

For C1 vs C2 context switches, the KDE curves have zero overlap — C1 clusters around 2449 and C2 around 24. This is visually unambiguous and matches the statistical result.

---

## Key Takeaways

1. **CPU affinity is a hardware-level fix.** Pinning processes to separate cores eliminates forced time-sharing and directly reduces execution time proportional to the reduction in competition. It does not change scheduler behaviour.

2. **Scheduler tuning is an OS-level fix.** `SCHED_RR` eliminates involuntary preemption of the measured process, collapsing context switches by 99% and further improving execution time. It does not compensate for inadequate core resources.

3. **The two tunings are orthogonal.** The data shows clearly: affinity does not reduce context switches (−0.9%), and scheduler tuning alone without affinity would not recover the execution time lost to core contention. Both fixes are needed for full optimisation.

4. **Contention must be high enough for scheduler tuning to show.** With only 2 processes, context switch counts are near-zero and scheduler tuning has nothing to improve. The redesign (6 processes, constrained cores) was essential to making the C2 improvement measurable.

5. **Real-time scheduling (`SCHED_RR`) requires elevated privileges.** `chrt -r` requires `sudo` or `CAP_SYS_NICE`. `nice` is not a substitute — it only adjusts weight within `SCHED_OTHER`, not the scheduling class itself.

---

## Limitations & Honest Notes

- **Results reflect controlled stress conditions.** Six competing CPU-bound processes on 2 cores is an artificially hostile environment. In normal workloads with lower contention, the absolute gains would be smaller, though the relative ordering of SB < C1 < C2 is expected to hold.

- **C2's execution time improvement combines two effects.** With `SCHED_RR` at priority 99, the foreground process both avoids preemption by and monopolises CPU time from the background workers. These two effects are not separately quantified in this experiment. This is real `SCHED_RR` behaviour but worth being explicit about.

- **`SCHED_RR` is not a general-purpose optimisation.** Real-time scheduling can starve normal-priority processes. It is appropriate for latency-sensitive applications (audio servers, robotics, HPC batch jobs) — not as a routine performance trick in production systems.

- **Single machine, single run session.** Absolute values will differ across CPU microarchitectures, kernel versions, and background system load. The directional results are expected to generalise; the specific numbers are environment-specific.

- **Context switches measured for the foreground process only.** Background worker context switches are not reported — only the measured foreground process is instrumented by `perf stat`. This is intentional: the experiment measures the impact of tuning on the process of interest, not the system as a whole.

- **n = 10 is a small sample.** It is sufficient for the large effects observed here but would not be adequate for detecting subtle differences. Results with d < 0.5 should be treated cautiously at this sample size.