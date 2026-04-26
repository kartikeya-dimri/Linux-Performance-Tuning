#!/usr/bin/env bash
# Sets FIFO RT priority on the current shell, then execs the workload.
# Must be run as root (via sudo).
chrt -f 99 taskset -c "$1" "$2" "$3"
