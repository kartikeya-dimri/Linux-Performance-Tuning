# Disk Performance Experiment — End-to-End Execution Guide

## Overview

This experiment implements a complete disk performance pipeline:

Collect → Analyze → Classify → Tune → Validate

The goal is to:

* Identify disk bottlenecks
* Apply targeted tuning
* Validate improvements using controlled workloads

---

## Prerequisites

### Install Required Tools

```bash
sudo apt install sysstat fio
pip install pandas matplotlib
```

### Make Scripts Executable

```bash
chmod +x run_workload.sh
chmod +x run_monitoring.sh
chmod +x run_experiment.sh
```

---

## Step 1 — Identify Disk Device

Find your disk device name:

```bash
lsblk
```

Examples:

* sda
* nvme0n1

You will need this during tuning.

---

## Step 2 — Ensure Clean System State

Before running experiments:

* Close heavy applications
* Stop background downloads
* Avoid running other benchmarks

Check system idle state:

```bash
iostat -x 1
```

Expected:

* Low `%util`
* Low `await`

---

## Step 3 — Run Experiment

Start with the most important workload:

```bash
./run_experiment.sh rand
```

---

## Step 4 — What the Script Does

The pipeline executes automatically in the following phases:

### Phase A — Baseline (Before Tuning)

* Starts monitoring
* Runs workload (fio)
* Stores logs in:

  ```
  run_<timestamp>/
  ```

---

### Phase B — Feature Extraction

* Parses logs
* Generates:

  ```
  disk_features_full.json
  ```

---

### Phase C — Classification

* Determines:

  * DISK-BOUND or NOT DISK-BOUND
* Provides reasoning (latency, iowait, queue, etc.)

Expected (random workload):

```
DISK-BOUND
```

---

### Phase D — Tuning

* Suggests system-level tuning commands:

  * I/O scheduler
  * Read-ahead
  * Memory writeback

You must:

* Review commands
* Apply them manually
* Press ENTER to continue

---

### Phase E — Post-Tuning Run

* Same workload executed again
* New metrics collected

---

### Phase F — Plot Generation

Plots saved in:

```
comparison_plots/
```

Includes:

* utilization.png
* latency.png
* queue.png
* iowait.png
* throughput.png

---

## Step 5 — Validate Results

### Key Metrics to Compare

| Metric            | Expected Change    |
| ----------------- | ------------------ |
| Latency (`await`) | Decrease           |
| Queue (`aqu-sz`)  | Decrease           |
| IOWait (`wa`)     | Decrease           |
| Throughput        | Stable or Increase |

---

### Important Note

High disk utilization is not necessarily bad.

Focus on:

* Latency reduction
* Queue stabilization
* Reduced iowait

---

## Step 6 — Run Additional Workloads

Execute:

```bash
./run_experiment.sh mix
./run_experiment.sh seq
```

### Expected Behavior

| Workload | Expected Outcome       |
| -------- | ---------------------- |
| rand     | Strong disk bottleneck |
| mix      | Moderate bottleneck    |
| seq      | Minimal bottleneck     |

---

## Step 7 — Analyze Outputs

For each run, examine:

1. Classification output
2. Feature summary (JSON/CSV)
3. Plots (primary evidence)

---

## Directory Structure

```
run_<timestamp>/
    iostat.log
    vmstat.log
    disk_features_full.json

comparison_plots/
    utilization.png
    latency.png
    queue.png
    iowait.png
```

---

## Common Mistakes

Avoid the following:

* Running without monitoring
* Changing workload parameters between runs
* Forgetting `--direct=1` (causes cache interference)
* Applying all tunings blindly
* Using incorrect disk device name

---

## Final Outcome

A successful experiment demonstrates:

* Accurate bottleneck detection
* Effective tuning application
* Measurable performance improvement

---

## Notes

* Tuning changes are temporary (reset after reboot)
* Always validate results with identical workloads
* Focus on trends, not single values

---

## Recommended Execution Order

1. Random workload (rand)
2. Mixed workload (mix)
3. Sequential workload (seq)

---

## Conclusion

This pipeline provides a reproducible approach to:

* Diagnose disk performance issues
* Apply targeted optimizations
* Validate improvements using empirical data
