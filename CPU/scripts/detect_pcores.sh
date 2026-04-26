#!/usr/bin/env bash
# detect_pcores.sh — Find P-core physical CPU IDs on hybrid Intel CPUs
# Prints two P-core logical CPU IDs suitable for taskset pinning.
# On non-hybrid CPUs, prints cores 0 and 1.
#
# Detection method: P-cores have higher max_freq than E-cores.
# We rank all cores by max frequency and pick the top two PHYSICAL cores
# (avoiding hyperthreading siblings so both processes get a full core).

NCORES=$(nproc)
declare -A freq_map   # logical_cpu → max_freq
declare -A sibling_map

# Read max frequency for each logical CPU
for cpu in $(seq 0 $((NCORES - 1))); do
    freq_file="/sys/devices/system/cpu/cpu${cpu}/cpufreq/cpuinfo_max_freq"
    if [[ -f "$freq_file" ]]; then
        freq_map[$cpu]=$(cat "$freq_file")
    else
        freq_map[$cpu]=0
    fi
done

# Read thread siblings (to avoid picking two HT threads of same physical core)
for cpu in $(seq 0 $((NCORES - 1))); do
    sib_file="/sys/devices/system/cpu/cpu${cpu}/topology/thread_siblings_list"
    if [[ -f "$sib_file" ]]; then
        # thread_siblings_list is like "0,8" — we store the lowest sibling as canonical
        canonical=$(cat "$sib_file" | tr ',' '\n' | sort -n | head -1)
        sibling_map[$cpu]=$canonical
    else
        sibling_map[$cpu]=$cpu
    fi
done

# Sort CPUs by max_freq descending, pick first two with DIFFERENT physical cores
declare -A seen_physical
selected=()

while IFS= read -r cpu; do
    phys=${sibling_map[$cpu]}
    if [[ -z "${seen_physical[$phys]}" ]]; then
        seen_physical[$phys]=1
        selected+=("$cpu")
        if [[ ${#selected[@]} -eq 2 ]]; then
            break
        fi
    fi
done < <(
    for cpu in "${!freq_map[@]}"; do
        echo "${freq_map[$cpu]} $cpu"
    done | sort -rn | awk '{print $2}'
)

if [[ ${#selected[@]} -lt 2 ]]; then
    # Fallback: just use 0 and 1
    echo "0 1"
else
    echo "${selected[0]} ${selected[1]}"
fi
