# Memory Tuning — Experiment Results

> **Date:** _TBD (fill after running)_
> **System:** iiitb-vm (VirtualBox)
> **Tool:** stress-ng, vmstat, /proc/meminfo, /proc/pressure/memory
> **Duration:** 90s per run

---

## Experiment Design

Each workload is run twice: first with a deliberately **bad baseline** config, then with an **intelligent tuned** config recommended by `mem_tuning.py` based on extracted features.

| Workload | stress-ng Pattern | Bad Baseline | Tuned Config |
|----------|------------------|-------------|--------------|
| **alloc** | `--vm 4 --vm-bytes 75%` | swappiness=80, dirty=5/2, thp=never | swappiness=10, dirty=20/10, thp=always |
| **cache** | `--cache 4 --cache-size 256M` | swappiness=80, dirty=5/2, thp=never | swappiness=10, dirty=15/5, thp=madvise |
| **mix** | `--vm 2 + --cache 2` | swappiness=80, dirty=5/2, thp=never | swappiness=10, dirty=20/10, thp=madvise |

**Tuning logic:**
- Workload detected from swap rate (`avg_si_kBps + avg_so_kBps`) and major fault rate (`avg_pgmajfault`)
- Swappiness reduced based on free memory headroom and swap usage
- Dirty ratios set to allow write buffering and reduce flush-triggered eviction
- THP set based on workload type (always for anon-heavy, madvise for mixed)

---

## 1. Alloc Workload — ✅ Success

**Config:** stress-ng `--vm 4 --vm-bytes 2500M --vm-method walk-1d`, 90s
**Constraint:** 4 × 2500 MB = 10 GB total allocation > 8 GB physical RAM → forced swap

### Extracted Features

| Feature | Baseline (swappiness=200) | Tuned (swappiness=10) | Change |
|---------|--------------------------|----------------------|--------|
| `bogo_ops_per_s` | 106,486 | **240,995** | **+126% ✅** |
| `avg_iowait` | 22.8% | 1.9% | **−92% ✅** |
| `avg_pgfault` | 104,933/s | 22,500/s | **−79% ✅** |
| `avg_so_kBps` | 31,639 KB/s | 27,234 KB/s | −14% ✅ |
| `avg_swap_used_mb` | 679 MB | 221 MB | **−67% ✅** |
| `avg_free_mb` | 2,905 MB | 3,344 MB | +15% ✅ |
| `memory_pressure_score` | 7.47 | 5.55 | −26% ✅ |

### Statistical Significance (Mann-Whitney U)

| Metric | p-value | Significant? |
|--------|---------|-------------|
| Swap-Out (KB/s) | 8.54e-13 | **Yes** |
| Free Memory | 9.75e-12 | **Yes** |
| CPU iowait | 2.90e-22 | **Yes** |
| Pages Swapped Out/s | 6.96e-13 | **Yes** |

**Why it worked:** Bad baseline `swappiness=200` caused the kernel to swap pages out aggressively even under moderate pressure. With 10 GB allocated against 8 GB physical RAM, this meant constant swap thrashing — CPU spent 22.8% of time waiting on swap I/O. Tuned `swappiness=10` minimized eviction, letting workers keep their working set in RAM → 92% less iowait, 126% more throughput.

**Tuning applied:**
- `vm.swappiness` 200 → 10
- `vm.vfs_cache_pressure` 500 → 100  
- `vm.dirty_ratio` 5/2 → 20/10
- `vm.min_free_kbytes` 16384 → 262144
- THP: `never` → `always`

---

## 2. Cache Workload — _(Results pending)_

**Config:** stress-ng `--cache 4 --cache-size 256M`, 90s

### Extracted Features

| Feature | Baseline | Tuned | Change |
|---------|----------|-------|--------|
| `avg_free_mb` | TBD | TBD | TBD |
| `avg_pgmajfault` | TBD | TBD | TBD |
| `avg_si_kBps` | TBD | TBD | TBD |
| `avg_so_kBps` | TBD | TBD | TBD |
| `psi_some_avg10` | TBD | TBD | TBD |
| `memory_pressure_score` | TBD | TBD | TBD |

**Why it should work:** Bad baseline uses `dirty_ratio=5` (page cache dirtied by cache workload flushed far too often, causing write stalls). Tuned config raises dirty thresholds to allow natural write coalescing.

---

## 3. Mix Workload — _(Results pending)_

**Config:** stress-ng `--vm 2 --vm-bytes 50% --cache 2 --cache-size 256M`, 90s

### Extracted Features

| Feature | Baseline | Tuned | Change |
|---------|----------|-------|--------|
| `avg_free_mb` | TBD | TBD | TBD |
| `avg_pgmajfault` | TBD | TBD | TBD |
| `avg_si_kBps` | TBD | TBD | TBD |
| `avg_so_kBps` | TBD | TBD | TBD |
| `psi_some_avg10` | TBD | TBD | TBD |
| `memory_pressure_score` | TBD | TBD | TBD |

**Why it should work:** Combined bad config hits both anonymous memory (THP disabled, high swappiness) and cache workload (over-eager flusher). Tuned config addresses both axes simultaneously.

---

## Overall Summary

| Workload | Free Memory | Major Faults | Swap Rate | PSI Pressure | Verdict |
|----------|-------------|-------------|-----------|--------------|---------|
| **alloc** | TBD | TBD | TBD | TBD | _Pending_ |
| **cache** | TBD | TBD | TBD | TBD | _Pending_ |
| **mix** | TBD | TBD | TBD | TBD | _Pending_ |

---

## Tuning Decisions Summary

```mermaid
flowchart TD
    A[Extract Features] --> B{swap_rate > 20 KB/s?}
    B -- Yes --> C{pgmajfault > 50/s?}
    B -- No --> D{pgmajfault > 50/s?}
    C -- Yes --> E[Mixed Workload]
    C -- No --> F[Swap-Heavy Workload]
    D -- Yes --> G[Fault-Heavy Workload]
    D -- No --> E

    F --> H["swappiness=10, dirty=20/10, thp=always"]
    G --> I["swappiness=10, dirty=15/5, thp=madvise"]
    E --> J["swappiness=10, dirty=20/10, thp=madvise"]

    H --> K{avg_free_mb < 200?}
    I --> K
    J --> K
    K -- Yes --> L["swappiness=10 (aggressive)"]
    K -- No --> M["swappiness=30 (moderate)"]
```

## Key Takeaways _(to be filled after running)_

1. **vm.swappiness matters.** ...
2. **dirty_ratio must match write intensity.** ...
3. **THP is a meaningful accelerator for anon workloads.** ...
4. **PSI is a reliable health indicator.** ...
5. **Workload classification determines the right balance.** ...
