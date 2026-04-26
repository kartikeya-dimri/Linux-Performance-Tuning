# CPU Tuning — Controlled Experiment System

**Platform:** Intel Core Ultra 5 125H · Ubuntu · Kernel 7.x  
**Primary metric:** Wall-clock execution time  
**Secondary metric:** Execution time variance (stdev / stability)  
**Mechanistic metric:** CPU migrations (explains *why* time changes)  
**Validation:** Welch's t-test, 10 runs per state  

---

## Experiment Design

### Core Idea

We deliberately create a **worst-case baseline** (two processes locked to one core) and prove that kernel-level tunings fix it. This is not anecdotal — every claim is backed by 10-run Welch t-tests.

### The Four States

| State | Governor | Affinity | What it tests |
|-------|----------|----------|---------------|
| SA | powersave | cpu7+cpu5 | Clean single-process baseline |
| SB | powersave | **both on cpu7 only** | **Manufactured worst case** |
| C1 | powersave | cpu7 ↔ cpu5 split | Affinity split effect only |
| C2 | **performance** | cpu7 ↔ cpu5 split | Governor effect on top of affinity |

### Variable Isolation

```
SB → C1 : only affinity changes       → proves affinity alone fixes contention
C1 → C2 : only governor changes       → proves governor adds stability
SB → C2 : both change simultaneously  → headline combined improvement
```

### Why SB Is Deliberately Bad

Both processes are `taskset`-locked to a single P-core (cpu7). The Linux scheduler **cannot** migrate them off — taskset is a hard constraint. Both threads fight for the same:
- Execution units (ALU, FPU)
- L1/L2 cache
- Decode pipeline

Result: wall time roughly doubles vs SA. This is the problem being solved.

### Metrics

| Metric | Tool | Role |
|--------|------|------|
| Wall-clock time (mean) | `/usr/bin/time` | Primary — did it get faster? |
| Wall-clock time (stdev) | computed from 10 runs | Secondary — did it get more stable? |
| CPU migrations | `perf stat -e cpu-migrations` | Mechanistic — explains the mechanism |

---

## Project Structure

```
CPU_Tuning/
├── workload/
│   ├── prime.c              ← Deterministic CPU stressor (pthreads, 25M primes)
│   ├── build.sh             ← Compile
│   └── prime                ← Binary (after build)
├── scripts/
│   ├── common.sh            ← Shared config + measure_run() helper
│   ├── run_baselines.sh     ← SA + SB collection
│   ├── run_experiments.sh   ← C1 + C2 collection
│   └── analyze.sh           ← Stats + 5 plots + final report
├── results/
│   ├── raw/                 ← SA.csv SB.csv C1.csv C2.csv
│   └── plots/               ← 5 PNG figures
├── docs/
│   ├── environment.txt      ← Hardware snapshot
│   └── final_report.txt     ← Full statistical report
└── README.md
```

---

## Prerequisites

```bash
sudo apt install linux-tools-common linux-tools-generic linux-tools-$(uname -r) python3 time
pip3 install matplotlib scipy numpy --break-system-packages

# Allow perf without root
sudo sysctl -w kernel.perf_event_paranoid=1
```

---

## Execution

```bash
cd CPU_Tuning/

# Step 1: Build (~14s sanity test)
bash workload/build.sh

# Step 2: Run everything in sequence (~1 hour total)
bash scripts/run_baselines.sh && bash scripts/run_experiments.sh && bash scripts/analyze.sh
```

Do not touch the machine during runs. The scripts switch the governor automatically.

---

## Expected Results

| Comparison | Wall Time | Variance | Migrations |
|------------|-----------|----------|------------|
| SA vs SB | SB ~2x slower | SB higher variance | — |
| SB → C1 | Large improvement | Large reduction | ~100% reduction |
| C1 → C2 | Moderate improvement | Further reduction | Near zero already |
| SB → C2 | **Headline number** | **Dramatic reduction** | ~100% reduction |

---

## Claims

**What this proves:**  
Under controlled conditions, CPU affinity partitioning eliminates single-core contention and reduces execution time significantly. Adding the performance governor further reduces timing variance by locking CPU frequency.

**What this does NOT prove:**  
These results are specific to this hardware, kernel version, and workload. No universal performance guarantee is made.