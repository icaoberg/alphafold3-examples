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
# Rounds never overlap on a GPU type, so runs don't share nodes with each
# other: each round on a GPU type is submitted with a Slurm dependency on every
# job of the round before it on that GPU type (including jobs already in the
# queue), so it only starts once the previous round there has finished. GPU
# types are chained separately, so a slow V100 round doesn't hold up the H100.
# To queue all five rounds at once:
#   ./submit_sweep.sh -A <allocation-id> -r 1 -R 5
#
# Missing inputs are generated with gen_token_inputs.py.
#
# GPUS sets the GPU types (default: v100-32 l40s-48 h100-80).
# RESERVATIONS maps GPU types to reservations as space-separated <gpu>:<name>
# pairs (default: v100-32:GPUV100 l40s-48:GPUL40S h100-80:GPUH100). GPU types
# not listed are submitted without a reservation. Set RESERVATIONS= to never
# use one. A job's wall time is capped at the time left in its reservation,
# since Slurm won't start a job that would run past the reservation's end.
#
# A run is skipped if it already succeeded or is still queued or running, so
# the same rounds can be resubmitted to retry failed runs. Runs that ran out of
# memory are skipped too, since they would only fail again.

set -euo pipefail

GPUS=${GPUS-"v100-32 l40s-48 h100-80"}
RESERVATIONS=${RESERVATIONS-"v100-32:GPUV100 l40s-48:GPUL40S h100-80:GPUH100"}

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

# Reservation for a GPU type, or nothing if it has none.
reservation_for() {
  local pair
  for pair in $RESERVATIONS; do
    if [[ ${pair%%:*} == "$1" ]]; then
      echo "${pair#*:}"
      return
    fi
  done
}

# Whole minutes left before the GPU type's reservation ends, or nothing if it
# has no reservation or its end time can't be read.
reservation_minutes_left() {
  local res end
  res=$(reservation_for "$1")
  [[ -z "$res" ]] && return
  end=$(scontrol show reservation "$res" 2>/dev/null \
        | sed -n 's/.*EndTime=\([^ ]*\).*/\1/p')
  [[ -z "$end" ]] && return
  echo $(( ($(date -d "$end" +%s) - $(date +%s)) / 60 - 1 ))
}

# Wall-time limit for two seeds plus compilation, generous on purpose since
# L40S is slower than the A100/H100 in DeepMind's tables. V100 runs use the
# slower XLA attention, so they get twice as long; H100 runs get half as long.
# Capped at the time left in the GPU type's reservation.
walltime() {
  local n=$1 gpu=$2 minutes left
  if   (( n <= 1024 )); then minutes=30
  elif (( n <= 2048 )); then minutes=60
  elif (( n <= 3072 )); then minutes=120
  elif (( n <= 4096 )); then minutes=180
  else                       minutes=240
  fi
  [[ $gpu == v100* ]] && minutes=$((minutes * 2))
  [[ $gpu == h100* ]] && minutes=$((minutes / 2))
  left=$(reservation_minutes_left "$gpu")
  if [[ -n "$left" ]] && (( left > 0 && left < minutes )); then
    minutes=$left
  fi
  printf '%02d:%02d:00\n' $((minutes / 60)) $((minutes % 60))
}

suffix=""
(( mem == 1 )) && suffix=-mem

# "<job id> <job name>" for this user's queued and running jobs.
queue=$(squeue -u "${USER:-$(whoami)}" -h -o "%i %j" 2>/dev/null || true)

# Colon-separated job ids of a round's sweep jobs on one GPU type that are
# already queued or running.
queued_ids() {
  local round=$1 gpu=$2
  awk -v re="^af3-sweep-tokens[0-9]+-${gpu}-r${round}${suffix}\$" \
      '$2 ~ re {print $1}' <<< "$queue" | paste -sd: -
}

fake_id=900000   # job ids shown in dry runs

# Per GPU type, the colon-separated job ids of the previous round.
declare -A prev_ids ids
for gpu in $GPUS; do
  prev_ids[$gpu]=""
  if (( first > 1 )); then
    prev_ids[$gpu]=$(queued_ids $((first - 1)) "$gpu")
  fi
done

for (( round = first; round <= last; round++ )); do
  tag=r$round$suffix

  # This round's jobs already in the queue, per GPU type.
  for gpu in $GPUS; do
    ids[$gpu]=$(queued_ids "$round" "$gpu")
  done

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
      res=$(reservation_for "$gpu")
      [[ -n "$res" ]] && reservation=(--reservation="$res")

      dependency=()
      if [[ -n "${prev_ids[$gpu]}" ]]; then
        dependency=(--dependency="afterany:${prev_ids[$gpu]}")
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
      ids[$gpu]=${ids[$gpu]:+${ids[$gpu]}:}$id
    done
  done

  for gpu in $GPUS; do
    prev_ids[$gpu]=${ids[$gpu]}
  done
done
