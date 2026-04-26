#!/usr/bin/env bash
# detect_pcores.sh — Find two P-core logical CPU IDs on hybrid Intel CPUs
#
# Strategy:
#   1. Read cpuinfo_max_freq for every logical CPU
#   2. Rank by max frequency (P-cores are highest)
#   3. Pick two that belong to DIFFERENT physical cores (no HT siblings)
#
# Output: two space-separated CPU IDs, e.g. "5 7"
# On non-hybrid CPUs: falls back to "0 1"

NCORES=$(nproc)
declare -A freq_map
declare -A sibling_map

for cpu in $(seq 0 $((NCORES-1))); do
    f="/sys/devices/system/cpu/cpu${cpu}/cpufreq/cpuinfo_max_freq"
    freq_map[$cpu]=$(cat "$f" 2>/dev/null || echo 0)
done

for cpu in $(seq 0 $((NCORES-1))); do
    s="/sys/devices/system/cpu/cpu${cpu}/topology/thread_siblings_list"
    if [[ -f "$s" ]]; then
        canonical=$(cat "$s" | tr ',' '\n' | sort -n | head -1)
        sibling_map[$cpu]=$canonical
    else
        sibling_map[$cpu]=$cpu
    fi
done

declare -A seen
selected=()

while IFS= read -r cpu; do
    phys=${sibling_map[$cpu]}
    if [[ -z "${seen[$phys]}" ]]; then
        seen[$phys]=1
        selected+=("$cpu")
        [[ ${#selected[@]} -eq 2 ]] && break
    fi
done < <(
    for cpu in "${!freq_map[@]}"; do
        echo "${freq_map[$cpu]} $cpu"
    done | sort -rn | awk '{print $2}'
)

if [[ ${#selected[@]} -lt 2 ]]; then
    echo "0 1"
else
    echo "${selected[0]} ${selected[1]}"
fi
