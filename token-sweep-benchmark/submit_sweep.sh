#!/bin/bash
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only

# Submit one round of the token-size sweep: every input size on every GPU
# type, one job each.
#
# Usage, from this directory:
#   ./submit_sweep.sh -A <allocation-id> [-r <repeat>] [-m] [-n] [size ...]
#
#   -A  allocation to charge
#   -r  repeat number (default 1); submit the next round only after the
#       previous one finishes, so runs don't share nodes with each other
#   -m  memory-profiling round (AF3_MEMPROFILE=1); kept apart from timing runs
#   -n  dry run: print the sbatch commands without submitting
#   size ...  token sizes to run (default: every inputs/tokens*.json)
#
# Missing inputs are generated with gen_token_inputs.py.
#
# Set GPUS to change the GPU types (default: l40s-48), e.g.
#   GPUS="v100-32 l40s-48 h100-80" ./submit_sweep.sh ...
# Set RESERVATION to change the reservation (default: alphafold3), or to an
# empty string to submit without one, e.g. for GPU types the reservation
# doesn't cover:
#   RESERVATION= GPUS="v100-32 h100-80" ./submit_sweep.sh ...
#
# A run is skipped if it already succeeded or is still queued or running, so
# the same round can be resubmitted to retry failed runs. Runs that ran out of
# memory are skipped too, since they would only fail again.

set -euo pipefail

GPUS=${GPUS-"l40s-48"}
RESERVATION=${RESERVATION-"alphafold3"}

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

if [[ -z "$account" || ! "$repeat" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 -A <allocation-id> [-r <repeat>] [-m] [-n] [size ...]" >&2
  exit 2
fi

cd "$(dirname "$(realpath "$0")")"
mkdir -p logs

# Generate the default sizes if there are no inputs at all.
if ! compgen -G "inputs/tokens*.json" > /dev/null; then
  ./gen_token_inputs.py
fi

if (( $# > 0 )); then
  sizes=("$@")
  # Generate any requested size that does not have an input yet.
  missing=()
  for n in "${sizes[@]}"; do
    [[ -f inputs/tokens$n.json ]] || missing+=("$n")
  done
  if (( ${#missing[@]} > 0 )); then
    ./gen_token_inputs.py "${missing[@]}"
  fi
else
  sizes=($(ls inputs/tokens*.json | sed 's/.*tokens\([0-9]*\)\.json/\1/' | sort -n))
fi

# Wall-time limit for two seeds plus compilation, generous on purpose since
# L40S is slower than the A100/H100 in DeepMind's tables. V100 runs use the
# slower XLA attention, so they get twice as long.
walltime() {
  local n=$1 gpu=$2 minutes
  if   (( n <= 1024 )); then minutes=30
  elif (( n <= 2048 )); then minutes=60
  elif (( n <= 3072 )); then minutes=120
  elif (( n <= 4096 )); then minutes=180
  else                       minutes=240
  fi
  [[ $gpu == v100* ]] && minutes=$((minutes * 2))
  printf '%02d:%02d:00\n' $((minutes / 60)) $((minutes % 60))
}

reservation=()
[[ -n "$RESERVATION" ]] && reservation=(--reservation="$RESERVATION")

queued=$(squeue -u "${USER:-$(whoami)}" -h -o %j 2>/dev/null || true)

for n in "${sizes[@]}"; do
  for gpu in $GPUS; do
    tag=r$repeat
    (( mem == 1 )) && tag=$tag-mem
    name=af3-sweep-tokens$n-$gpu-$tag

    if grep -qx "$name" <<< "$queued"; then
      echo "skip $name: queued or running"
      continue
    fi
    if grep -lqs "^Done running" logs/"$name"-*.out; then
      echo "skip $name: already done"
      continue
    fi
    if grep -lqsi "RESOURCE_EXHAUSTED\|out of memory" logs/"$name"-*.out; then
      echo "skip $name: ran out of memory before"
      continue
    fi

    cmd=(sbatch --parsable -A "$account" "${reservation[@]}"
         --gpus="$gpu:1" --job-name="$name"
         --time="$(walltime "$n" "$gpu")"
         --export=ALL,AF3_GPU="$gpu",AF3_REPEAT="$repeat",AF3_MEMPROFILE="$mem"
         sweep.sh "inputs/tokens$n.json")
    if $dry_run; then
      echo "${cmd[*]}"
    else
      echo "submitted $name: $("${cmd[@]}")"
    fi
  done
done
