#!/bin/bash
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only

# Submit rounds of the token-size sweep: in each round, every input size on
# every GPU type, one job each.
#
# Usage, from this directory:
#   ./submit_sweep.sh -A <allocation-id> [-r <first>] [-R <last>] [-m] [-n] [size ...]
#
#   -A  allocation to charge
#   -r  first round (repeat number) to submit (default 1)
#   -R  last round to submit (default: same as -r, i.e. one round)
#   -m  memory-profiling rounds (AF3_MEMPROFILE=1); kept apart from timing runs
#   -n  dry run: print the sbatch commands without submitting
#   size ...  token sizes to run (default: every inputs/tokens*.json)
#
# Rounds never overlap, so runs don't share nodes with each other: each round
# is submitted with a Slurm dependency on every job of the round before it
# (including jobs of that round already in the queue), so it only starts once
# the previous round has finished. To queue all five rounds at once:
#   ./submit_sweep.sh -A <allocation-id> -r 1 -R 5
#
# Missing inputs are generated with gen_token_inputs.py.
#
# GPUS sets the GPU types (default: v100-32 l40s-48 h100-80).
# RESERVATION sets the reservation (default: alphafold3), used only for the
# GPU types listed in RESERVATION_GPUS (default: l40s-48); other GPU types are
# submitted without a reservation. Set RESERVATION= to never use one.
#
# A run is skipped if it already succeeded or is still queued or running, so
# the same rounds can be resubmitted to retry failed runs. Runs that ran out of
# memory are skipped too, since they would only fail again.

set -euo pipefail

GPUS=${GPUS-"v100-32 l40s-48 h100-80"}
RESERVATION=${RESERVATION-"alphafold3"}
RESERVATION_GPUS=${RESERVATION_GPUS-"l40s-48"}

account=""
first="1"
last=""
mem=0
dry_run=false
while getopts "A:r:R:mn" opt; do
  case $opt in
    A) account=$OPTARG ;;
    r) first=$OPTARG ;;
    R) last=$OPTARG ;;
    m) mem=1 ;;
    n) dry_run=true ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
last=${last:-$first}

usage="Usage: $0 -A <allocation-id> [-r <first>] [-R <last>] [-m] [-n] [size ...]"
if [[ -z "$account" || ! "$first" =~ ^[0-9]+$ || ! "$last" =~ ^[0-9]+$ ]] \
   || (( last < first )); then
  echo "$usage" >&2
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

suffix=""
(( mem == 1 )) && suffix=-mem

# "<job id> <job name>" for this user's queued and running jobs.
queue=$(squeue -u "${USER:-$(whoami)}" -h -o "%i %j" 2>/dev/null || true)

# Job ids of a round's sweep jobs that are already queued or running.
queued_ids() {
  local round=$1
  awk -v re="^af3-sweep-tokens[0-9]+-.*-r${round}${suffix}\$" \
      '$2 ~ re {print $1}' <<< "$queue"
}

fake_id=900000   # job ids shown in dry runs
prev_ids=()
if (( first > 1 )); then
  prev_ids=($(queued_ids $((first - 1))))
fi

for (( round = first; round <= last; round++ )); do
  tag=r$round$suffix
  ids=($(queued_ids "$round"))   # this round's jobs already in the queue

  dependency=()
  if (( ${#prev_ids[@]} > 0 )); then
    dependency=(--dependency="afterany:$(IFS=:; echo "${prev_ids[*]}")")
    echo "round $round: waits for ${#prev_ids[@]} job(s) of round $((round - 1))"
  fi

  for n in "${sizes[@]}"; do
    for gpu in $GPUS; do
      name=af3-sweep-tokens$n-$gpu-$tag

      if awk -v n="$name" '$2 == n {found=1} END {exit !found}' <<< "$queue"; then
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

      reservation=()
      if [[ -n "$RESERVATION" && " $RESERVATION_GPUS " == *" $gpu "* ]]; then
        reservation=(--reservation="$RESERVATION")
      fi

      cmd=(sbatch --parsable -A "$account" "${reservation[@]}"
           "${dependency[@]}"
           --gpus="$gpu:1" --job-name="$name"
           --time="$(walltime "$n" "$gpu")"
           --export=ALL,AF3_GPU="$gpu",AF3_REPEAT="$round",AF3_MEMPROFILE="$mem"
           sweep.sh "inputs/tokens$n.json")
      if $dry_run; then
        echo "${cmd[*]}"
        id=$((fake_id++))
      else
        id=$("${cmd[@]}")
        id=${id%%;*}   # --parsable may print "id;cluster"
        echo "submitted $name: $id"
      fi
      ids+=("$id")
    done
  done

  prev_ids=("${ids[@]}")
done
