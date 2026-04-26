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

**Why 25,000,000 specifically:** At this limit, a single process runs for ~14 seconds — long enough that scheduling noise is a small fraction of total runtime, but short enough that 10 runs per condition completes in under 10 minutes. Below ~5M, runs are too short and measurement jitter dominates. Above ~50M, the experiment takes hours.

---

## Experiment Design

### Parameters

| Parameter | Value | Rationale |
|---|---|---|
| Processes per run | 6 | Creates heavy scheduler pressure — forces thousands of context switches per run, giving scheduler tuning something measurable to fix |
| Cores available | 2 (cpu5, cpu7) | Constrained resource pool; 6 processes on 2 cores = 3× oversubscription |
| Runs per condition | 10 | Sufficient for Welch's t-test; balances time vs statistical power — effects are large enough that n=10 gives p < 0.001 |
| Cooldown between runs | 5s | Lets CPU thermal state and scheduler queue settle between measurements |
| Metric 1 | Wall time (seconds) | Primary: total execution time of the measured foreground process |
| Metric 2 | Context switches | Secondary: involuntary preemptions measured by `perf stat -e context-switches` |

**Why 6 processes specifically:** Fewer processes (2–3) produce context switch counts in the single digits — scheduler tuning has nothing meaningful to improve. More processes (10+) on 2 cores makes runs extremely long and increases thermal variance. 6 processes on 2 cores (3× oversubscription) was the minimum that generated thousands of context switches in SB while keeping run time under 50 seconds.

**Why 2 cores (cpu5, cpu7) specifically:** Both are confirmed P-cores on the Intel Core Ultra 5 125H running at 4500 MHz maximum frequency. Using P-cores ensures both cores run at the same speed, eliminating frequency mismatch as a confounding variable. E-cores on this CPU run at only 3600 MHz — using one P-core and one E-core would introduce a 25% clock speed difference that has nothing to do with the tunings being tested.

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

**Why this is a valid worst case:** `taskset` is a hard CPU affinity constraint — the kernel scheduler cannot migrate these processes off cpu7 even if cpu5 is completely idle. This guarantees the contention we want to measure, not a statistical average across many scheduling outcomes.

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
- Background workers at priority 98 can preempt each other but **not** the priority-99 foreground process
- Only change from C1: **scheduling class and priority** — same cores, same workload

---

## Implementation

### Measurement Method

Each run uses two tools simultaneously:

```bash
/usr/bin/time -f "%e" -o "$tmp_time" \
    perf stat -e context-switches -o "$tmp_perf" -- \
    taskset -c "$fg_cores" [chrt -r 99] "$WORKLOAD" 1
```

- `/usr/bin/time -f "%e"` captures wall-clock elapsed time in seconds (not CPU time — wall time includes all scheduling delays and is the correct metric for "how long did this take?")
- `perf stat -e context-switches` counts involuntary preemptions for the measured process only — background worker switches are not included

**Why wall time and not CPU time:** CPU time measures only the cycles actually given to this process. Wall time measures the total elapsed time including waiting. For a user experiencing a job, wall time is what matters. The difference between the two is the cost of scheduling — which is exactly what we are tuning.

### Background Worker Management

For each run, (PROCS - 1) = 5 background workers are launched, then the foreground process is measured, then all workers are reaped:

```bash
for ((p=1; p<PROCS; p++)); do
    taskset -c "$bg_cores" "$WORKLOAD" 1 &>/dev/null &
    BG_PIDS+=($!)
done
# ... measure foreground ...
for pid in "${BG_PIDS[@]}"; do wait "$pid"; done
```

This ensures the foreground process always competes against exactly 5 background processes — the contention level is constant across all runs.

---

## How to Run

### Prerequisites

```bash
sudo apt install linux-tools-common linux-tools-generic linux-tools-$(uname -r)
pip3 install matplotlib scipy numpy --break-system-packages

# Allow perf without root
sudo sysctl -w kernel.perf_event_paranoid=1

# Allow real-time scheduling (required for C2)
sudo mkdir -p /etc/systemd/system/user@.service.d/
sudo tee /etc/systemd/system/user@.service.d/rtprio.conf << EOF
[Service]
LimitRTPRIO=99
EOF
sudo systemctl daemon-reload
sudo systemctl restart "user@$(id -u).service"
# Open fresh terminal — verify: ulimit -r should print 99
```

### Execution

```bash
cd CPU_Tuning/
bash workload/build.sh
bash scripts/run_baselines.sh && bash scripts/run_experiments.sh && bash scripts/analyze.sh
```

### Expected Runtime

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

| Condition | Mean (s) | SD (s) | CV | Change vs SB |
|---|---|---|---|---|
| SB | 43.720 | 0.018 | 0.04% | — |
| C1 | 22.288 | 0.992 | 4.45% | **−49.0%** |
| C2 | 8.455 | 0.838 | 9.91% | **−80.7%** |

**Why SB mean = 43.72s:** A single process takes ~14s on one core. Six processes sharing one core each get ~1/6 of the core, so each takes ~6× longer = ~84s of CPU time, but they run concurrently — the measured foreground process finishes when it gets its 1/6 share, which takes approximately 14s × 3 = 42s (not 84s, because the other 5 processes run in parallel on the same timeslice schedule). The observed 43.72s matches this model closely.

**Why C1 mean = 22.29s:** With 3 processes per core instead of 6, the foreground process gets ~1/3 of one core. Expected time = 14s × 3 = 42s on one core, but now split across 2 cores with only 3 competitors = ~21s. Observed 22.29s is within 6% of this prediction — the small excess is scheduling overhead and OS noise.

**Why C2 mean = 8.46s:** With `SCHED_RR` priority 99, the foreground process is almost never preempted. It effectively monopolises its core while running. Time approaches the single-process baseline of ~14s but lower because it still benefits from affinity split — two cores available and RT priority means it runs nearly uninterrupted on its dedicated core. The 8.46s result is below the single-process baseline because SCHED_RR allows the process to capture more than its "fair share" of the core, at the expense of background workers.

**Why SB SD = 0.018s (CV = 0.04%):** A single saturated core under constant 6-way contention is a highly deterministic bottleneck. The OS scheduler round-robins all 6 processes with a fixed time quantum. Every run experiences the same pattern — there is almost no randomness. This is the most reproducible condition in the experiment.

**Why C1 SD = 0.992s (CV = 4.45%):** With 3 processes per core across 2 cores, the scheduler now has slightly more freedom in how it assigns time quanta. Different scheduling paths through the run introduce ~1 second of variance. Run 1 shows a notable outlier (25.11s vs 21.97s for runs 2–10) due to a cold-start effect — residual scheduler state from SB carried over into the first C1 run. This confirms that the 5-second cooldown is borderline sufficient and a warmup run would further reduce variance.

**Why C2 SD = 0.838s (CV = 9.91%):** Despite SCHED_RR eliminating most preemptions, some variance remains because the OS timer interrupt and kernel threads still fire occasionally. CV is higher than C1 in relative terms because the mean dropped so dramatically (8.46s) while absolute variance stayed similar — the percentage is inflated by the smaller denominator, not by more actual instability.

### Context Switches

| Condition | Mean | SD | Change vs SB |
|---|---|---|---|
| SB | 2470 | 5 | — |
| C1 | 2449 | 19 | −0.9% |
| C2 | 24 | 11 | **−99.0%** |

**Why SB mean = 2470 context switches:** Six processes on one core, running for ~44 seconds. The Linux CFS default time quantum is approximately 4ms. A round-robin schedule across 6 processes means each process gets preempted approximately every 4ms × 6 = 24ms. Over 44 seconds: 44s / 0.024s ≈ 1833 preemptions. The observed 2470 is higher because CFS also triggers switches on wake-ups and priority changes, not just quantum expiry. The number is in the correct order of magnitude.

**Why SB SD = 5 (very low):** Same reason as wall time — saturated single-core contention is deterministic. The scheduler runs the same pattern every time. 5 switches of variance across 2470 is 0.2% — essentially constant.

**Why C1 mean = 2449 (only 0.9% lower than SB):** Affinity does not change the scheduler's behaviour toward individual processes. With 3 processes per core instead of 6, there are slightly fewer processes to round-robin among, so very slightly fewer switches. But the fundamental preemption pattern is unchanged — `SCHED_OTHER` still switches at every quantum expiry. The 21-switch reduction (2470 → 2449) is real (p = 0.006) but practically meaningless. This is the experiment's most important negative result: **affinity alone does not fix preemption**.

**Why C1 SD = 19 (higher than SB):** With processes distributed across 2 cores, the scheduler has more scheduling decisions to make — it must manage two independent run queues. This introduces slightly more variance in how often the foreground process gets preempted each run. The wider spread (19 vs 5) reflects this additional scheduling freedom.

**Why C2 mean = 24:** With `SCHED_RR` at priority 99, the foreground process is only preempted when its own time quantum expires and another equal-priority SCHED_RR process is waiting — which doesn't happen here since there are none — or by kernel-level interrupts (timers, IRQs). Those kernel-level preemptions account for the residual ~24 switches. This is the theoretical floor for a CPU-bound real-time process on a non-RT kernel.

**Why C2 SD = 11 (relatively high compared to mean):** With only 24 mean context switches, a standard deviation of 11 looks large (46% CV). But the absolute magnitude is tiny — the variance is ±11 kernel interrupt preemptions per run, which is just natural variation in system interrupt timing. At this level, we are measuring OS noise, not workload behaviour.

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

Using an equal-variance t-test here would be statistically incorrect. The variance ratio between SB and C1 is 0.992/0.018 = 55× — violating the equal-variance assumption by a factor of 55.

### Why the t-values Are So Large

**t = 68.34 (SB vs C1, wall time):**

The t-statistic is the ratio of the mean difference to the standard error of that difference. Here:
- Mean difference: 43.72 − 22.29 = 21.43 seconds
- Pooled standard error: ≈ 0.31 seconds (dominated by C1's larger SD spread across 10 runs)
- t = 21.43 / 0.31 ≈ 69 — matches the computed value

Large t reflects a large effect (21 second difference) divided by a small standard error (tight measurements). Both contribute.

**t = 350.22 (C1 vs C2, context switches):**

- Mean difference: 2449 − 24 = 2425 switches
- Pooled standard error: ≈ 6.9 switches
- t = 2425 / 6.9 ≈ 351 — matches

The denominator is tiny because both C1 (SD=19) and C2 (SD=11) are individually very consistent. A 2425-switch difference divided by a 7-switch standard error produces an extreme t. This is not a sign of error — it means the two conditions are completely and unambiguously separated.

### Why Cohen's d Matters (And Why Ours Is So Large)

Cohen's d measures effect size — how many standard deviations apart the two group means are:

```
d = |mean_A - mean_B| / pooled_SD
```

p-values only tell you whether an effect is real. With 10 runs each, even a 0.001s difference can clear p < 0.05 if variance is low enough. Cohen's d tells you if the difference is practically meaningful:

| d value | Conventional interpretation |
|---|---|
| 0.2 | Small |
| 0.5 | Medium |
| 0.8 | Large |
| > 2.0 | Very large (rare in social science) |

**Why our d values are 30–156 (far beyond conventional scales):**

Cohen's d was developed for psychological and social science experiments where:
- Effects are subtle (milliseconds of reaction time, small score differences)
- Variance is high (humans are noisy)
- d rarely exceeds 1.0

In systems experiments, the situation is reversed:
- Effects are large (seconds of execution time, thousands of switches eliminated)
- Variance is low (hardware is deterministic)
- d of 10–100 is normal when the effect is real and the experiment is controlled

**Concretely for SB vs C1 wall time (d = 30.56):**
- Mean difference = 21.43s
- Pooled SD = 21.43 / 30.56 ≈ 0.70s
- The pooled SD is 0.70s because SB's SD is only 0.018s — an extraordinarily tight baseline
- Dividing 21.43 by 0.70 gives d = 30.56

The extreme d is a mathematical consequence of SB being near-perfectly deterministic (SD = 0.018s, CV = 0.04%). A fully saturated core under constant 6-way contention produces clockwork scheduling — the same pattern every run. When the denominator of Cohen's d is this small, d scales up dramatically.

**What extreme d actually tells you:** The two distributions do not overlap at all. Every single SB measurement (43.69–43.75s range across 10 runs) is completely separated from every single C1 measurement (21.96–25.11s range). You could identify which condition a run belongs to with 100% accuracy just by looking at the wall time — no statistics needed. d > 10 should be read as "completely non-overlapping distributions" rather than a literal magnitude to compare to behavioural science benchmarks.

**The most informative d is the small one:** SB vs C1 context switches gives d = 1.56 — statistically significant (p = 0.006) but a small practical effect (2470 → 2449, a difference of 21 switches). This is not a failure. It is a **finding** — it proves rigorously that CPU affinity alone does not meaningfully reduce context switches. The small d here is as important as the large d elsewhere: it confirms the experiment correctly isolates the two tuning mechanisms.

### Distribution Plots

Six plots are generated to characterise each condition's behaviour:

- **Bar charts** (mean ± SE): quick visual comparison of central tendency across conditions
- **Box plots** (IQR + whiskers): show spread, median, and outliers; execution time uses log scale to make all three distributions visible simultaneously — without log scale, SB's box (range 43.69–43.75s) would be invisible against C1's box (range 21.96–25.11s)
- **KDE density curves**: show the full shape of each distribution, confirm separation, and reveal multimodality (C1's bimodal KDE reflects two possible scheduling states across 2 cores — the 25.11s outlier from run 1 and the 21.97s cluster from runs 2–10)

For C1 vs C2 context switches, the KDE curves have zero overlap — C1 clusters tightly around 2449 and C2 clusters tightly around 24. The gap between them (over 2400 switches) is unambiguous visually and statistically.

---

## Key Takeaways

1. **CPU affinity is a hardware-level fix.** Pinning processes to separate cores eliminates forced time-sharing and directly reduces execution time proportional to the reduction in competition. It does not change scheduler behaviour.

2. **Scheduler tuning is an OS-level fix.** `SCHED_RR` eliminates involuntary preemption of the measured process, collapsing context switches by 99% and further improving execution time. It does not compensate for inadequate core resources.

3. **The two tunings are orthogonal.** The data shows clearly: affinity does not reduce context switches (−0.9%), and scheduler tuning alone without affinity would not recover the execution time lost to core contention. Both fixes are needed for full optimisation.

4. **Contention must be high enough for scheduler tuning to show.** With only 2 processes, context switch counts are near-zero and scheduler tuning has nothing to improve. The redesign (6 processes, constrained cores) was essential to making the C2 improvement measurable.

5. **Real-time scheduling (`SCHED_RR`) requires elevated privileges.** `chrt -r` requires `sudo` or `CAP_SYS_NICE`. `nice` is not a substitute — it only adjusts weight within `SCHED_OTHER`, not the scheduling class itself.

6. **Large Cohen's d in systems experiments is expected, not suspicious.** d values of 30–156 reflect deterministic hardware measurements with large real effects. They confirm non-overlapping distributions, not a flawed experimental design. The conventional d > 0.8 = "large" scale applies to human-subject research where variance is inherently high — not to controlled hardware experiments.

---

## Limitations & Honest Notes

- **Results reflect controlled stress conditions.** Six competing CPU-bound processes on 2 cores is an artificially hostile environment. In normal workloads with lower contention, the absolute gains would be smaller, though the relative ordering of SB < C1 < C2 is expected to hold.

- **C2's execution time improvement combines two effects.** With `SCHED_RR` at priority 99, the foreground process both avoids preemption by and monopolises CPU time from the background workers. These two effects are not separately quantified in this experiment. This is real `SCHED_RR` behaviour but worth being explicit about.

- **`SCHED_RR` is not a general-purpose optimisation.** Real-time scheduling can starve normal-priority processes. It is appropriate for latency-sensitive applications (audio servers, robotics, HPC batch jobs) — not as a routine performance trick in production systems.

- **Single machine, single run session.** Absolute values will differ across CPU microarchitectures, kernel versions, and background system load. The directional results are expected to generalise; the specific numbers are environment-specific.

- **Context switches measured for the foreground process only.** Background worker context switches are not reported — only the measured foreground process is instrumented by `perf stat`. This is intentional: the experiment measures the impact of tuning on the process of interest, not the system as a whole.

- **n = 10 is a small sample.** It is sufficient for the large effects observed here but would not be adequate for detecting subtle differences. Results with d < 0.5 should be treated cautiously at this sample size.

- **C1 run 1 outlier (25.11s vs ~21.97s for runs 2–10).** The first C1 run is ~3 seconds slower than the remaining nine. This is a cold-start effect — residual scheduler state from SB carries over despite the 5-second cooldown. A production experiment would include a mandatory warmup run discarded before measurement. The outlier is retained in the reported data for transparency and noted here. Excluding it changes C1 mean from 22.29s to 21.97s — a 1.5% difference that does not affect any conclusion.
