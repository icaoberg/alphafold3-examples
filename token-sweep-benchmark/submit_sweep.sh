#!/bin/bash
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only

# Submit the token-size sweep: one job per input size per GPU type.
#
# Usage, from this directory:
#   ./submit_sweep.sh -A <allocation-id> -r <repeat> [-m] [-n] [size ...]
#
#   -A  allocation to charge
#   -r  repeat number
#   -m  memory-profiling run (AF3_MEMPROFILE=1)
#   -n  dry run: print the sbatch commands only
#   size ...  token sizes to run (default: every inputs/tokens*.json)
#
# Set GPUS to change GPU types (default: l40s-48).
# Set RESERVATION to change the reservation (default: GPUpscstaff).

set -euo pipefail

GPUS=${GPUS:-"l40s-48"}
RESERVATION=${RESERVATION:-"GPUpscstaff"}
account=""
repeat="1"
mem=0
dry_run=false
while getopts "A:r:mn" opt; do
  case $opt in
    A) account=$OPTARG ;;
    r) repeat=$OPTARG ;;
    m) mem=1 ;;
    n) dry_run=true ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))

if [[ -z "$account" ]]; then
  echo "Usage: $0 -A <allocation-id> -r <repeat> [-m] [-n] [size ...]" >&2
  exit 2
fi

cd "$(dirname "$(realpath "$0")")"
mkdir -p logs

if (( $# > 0 )); then
  sizes=("$@")
else
  sizes=($(ls inputs/tokens*.json | sed 's/.*tokens\([0-9]*\)\.json/\1/' | sort -n))
fi

# Wall-time limit by size: two seeds plus compilation. Generous on purpose,
# since L40S is slower than the A100/H100 in DeepMind's tables.
walltime() {
  local n=$1
  if   (( n <= 1024 )); then echo 00:30:00
  elif (( n <= 2048 )); then echo 01:00:00
  elif (( n <= 3072 )); then echo 02:00:00
  else                       echo 04:00:00
  fi
}

for n in "${sizes[@]}"; do
  for gpu in $GPUS; do
    tag=r$repeat
    (( mem == 1 )) && tag=$tag-mem
    name=af3-sweep-tokens$n-$gpu-$tag
    cmd=(sbatch --parsable -A "$account" --reservation="$RESERVATION"
         --gpus="$gpu:1" --job-name="$name"
         --time="$(walltime "$n")"
         --export=ALL,AF3_GPU="$gpu",AF3_REPEAT="$repeat",AF3_MEMPROFILE="$mem"
         sweep.sh "inputs/tokens$n.json")
    if $dry_run; then
      echo "${cmd[*]}"
    else
      echo "submitted $name: $("${cmd[@]}")"
    fi
  done
done
