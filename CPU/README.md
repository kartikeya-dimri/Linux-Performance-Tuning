# CPU Performance Tuning — Experiment System

## Overview

A controlled experiment system that:
1. **Suggests** tunings based on detected system conditions (Phase 1)
2. **Proves** that tunings improve performance under controlled conditions (Phase 2)

---

## Project Structure

```
CPU/
├── workload/
│   ├── prime.c          ← CPU-bound stressor (pthread, deterministic)
│   ├── build.sh         ← Compile prime.c
│   └── prime            ← Compiled binary (after build)
├── scripts/
│   ├── measure.sh       ← Shared measurement helpers (sourced, not run directly)
│   ├── run_baseline.sh  ← Collect State A + State B measurements
│   ├── run_tuned.sh     ← Apply tunings, collect State C1 + C2
│   └── compare.sh       ← Statistical analysis + final report
├── results/             ← Auto-created, all CSVs and report go here
│   ├── environment.txt
│   ├── state_A.csv      ← Clean baseline
│   ├── state_B.csv      ← Synthetic contention
│   ├── state_C1.csv     ← Tuning 1: affinity split
│   ├── state_C2.csv     ← Tuning 2: affinity split + RT scheduling
│   └── final_report.txt
└── README.md
```

---

## Prerequisites

Install required tools (Ubuntu):

```bash
sudo apt update
sudo apt install linux-tools-common linux-tools-generic linux-tools-$(uname -r)
sudo apt install python3 time
```

---

## Step-by-Step Execution

### Step 1 — Build the workload

```bash
cd CPU/
bash workload/build.sh
```

### Step 2 — Prepare your environment

Before running experiments:
- Close all heavy applications (browsers, IDEs, etc.)
- Keep only a terminal open
- Do NOT touch the machine during runs

### Step 3 — Run baselines (State A and B)

```bash
bash scripts/run_baseline.sh
```

This collects:
- **State A**: clean system, no contention (true baseline)
- **State B**: two processes competing on same CPUs (the problem)

Each state runs **15 times**. Takes ~15–20 minutes.

### Step 4 — Run tuned experiments (State C1 and C2)

```bash
bash scripts/run_tuned.sh
```

This applies:
- **State C1**: CPU affinity split (process 1 → core 0, process 2 → core 1)
- **State C2**: Affinity split + FIFO real-time scheduling (chrt -f 99)

You will be prompted for sudo password for C2.

### Step 5 — Generate the report

```bash
bash scripts/compare.sh
```

Prints and saves `results/final_report.txt` with:
- Mean, stdev, stderr per state
- % improvement (wall time + migrations)
- Welch's t-test (statistical significance)
- Isolation of RT scheduling contribution

---

## Experiment Design (Why 4 States)

| State | Description | Purpose |
|-------|-------------|---------|
| A | Clean, no contention | True system baseline |
| B | Contention, same CPUs | The problem being solved |
| C1 | Affinity split | Tuning 1 |
| C2 | Affinity split + RT | Tuning 2 (isolates RT contribution) |

**Key comparison: B → C1 → C2** (not A → C)

---

## Metric Definitions

| Metric | Tool | Why |
|--------|------|-----|
| Wall-clock time | `/usr/bin/time` | Primary performance indicator |
| CPU migrations | `perf stat -e cpu-migrations` | Explains scheduling inefficiency |

Intentionally excluded: CPU utilization, context switches, cache metrics.

---

## Claims

**What this proves:**
> Under controlled conditions, CPU affinity splitting reduces wall-clock time
> and CPU migrations when two competing processes are pinned to separate
> physical cores instead of sharing a CPU set.

**What this does NOT prove:**
> These results are specific to this machine, kernel version, and workload.
> No universal performance guarantee is made.
