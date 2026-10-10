#!/bin/bash
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
#
# Written by Ivan Cao-Berg and River Zhu.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 as published by
# the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# SPDX-License-Identifier: GPL-2.0-only

# Submit every example with all its replicates: stage 1 (RM-shared) and
# stage 2 (GPU-shared) as job arrays, with stage 2 task N starting when
# stage 1 task N succeeds.
#
# Usage, from any directory:
#   ./submit.sh -A <allocation-id> [-r <replicates>] [-g <gpu>] [-n] [example ...]
#
#   -A  allocation to charge
#   -r  replicates to run, as a Slurm --array range (default 1-5)
#   -g  GPU type for stage 2 (default l40s-48), e.g. v100-32 or h100-80
#   -n  dry run: print the sbatch commands without submitting
#   example ...  directories to run (default: every example*/ here)
#
# Set RESERVATION to submit stage 2 to a reservation, e.g.
#   RESERVATION=alphafold3 ./submit.sh -A <allocation-id>
#
# Replicates that already have a predicted structure
# (output/replicate-N/<name>/<name>_model.cif) are skipped, and so are
# examples with jobs still queued or running, so the same command can be
# resubmitted to retry failed replicates.

# Abort on any failed command (-e), unset variable (-u) or failure inside a
# pipeline (-o pipefail).
set -euo pipefail

# Optional Slurm reservation for stage 2, taken from the environment. ${VAR-""}
# (no colon) keeps an explicitly empty value and still satisfies set -u.
RESERVATION=${RESERVATION-""}

# Defaults, overridden by the command-line flags parsed below.
account=""
replicates="1-5"
gpu="l40s-48"
dry_run=false
while getopts "A:r:g:n" opt; do
  case $opt in
    A) account=$OPTARG ;;
    r) replicates=$OPTARG ;;
    g) gpu=$OPTARG ;;
    n) dry_run=true ;;
    *) exit 2 ;;  # getopts already printed the error for an unknown flag
  esac
done
# Drop the parsed flags so "$@" holds only the example directories.
shift $((OPTIND - 1))

# An allocation is required, and the replicates must look like a Slurm
# --array range: comma-separated numbers or N-M ranges, e.g. 1-5 or 1-3,5.
if [[ -z "$account" || ! "$replicates" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]]; then
  echo "Usage: $0 -A <allocation-id> [-r <replicates>] [-g <gpu>] [-n] [example ...]" >&2
  exit 2
fi

# Work from the directory holding this script, so it can be called from
# anywhere and example paths resolve relative to vanilla-examples/.
cd "$(dirname "$(realpath "$0")")"

# Examples named on the command line (trailing slashes stripped, so tab
# completion works), or else every example*/ directory in natural order
# (example2 before example10).
if (( $# > 0 )); then
  examples=("${@%/}")
else
  examples=($(ls -d example*/ | tr -d / | sort -V))
fi

# Expand a range like 1-3,5 into "1 2 3 5".
expand() {
  local part
  for part in ${1//,/ }; do
    if [[ $part == *-* ]]; then seq "${part%-*}" "${part#*-}"; else echo "$part"; fi
  done
}

# Build the --reservation option only when RESERVATION is set; an empty array
# expands to nothing in the sbatch command below.
reservation=()
[[ -n "$RESERVATION" ]] && reservation=(--reservation="$RESERVATION")

# Names of this user's jobs that are pending or running, one per line, taken
# once up front. Tolerate squeue failing (e.g. on a node without Slurm) so a
# dry run still works.
queued=$(squeue -u "${USER:-$(whoami)}" -h -o %j 2>/dev/null || true)

for example in "${examples[@]}"; do
  # Every example needs its AlphaFold 3 input; skip stray directories.
  if [[ ! -f $example/fold_input.json ]]; then
    echo "skip $example: no fold_input.json"
    continue
  fi
  # Don't double-submit: an example with either stage still in the queue is
  # left alone until those jobs finish.
  if grep -qx "af3-\(data\|inference\)-$example" <<< "$queued"; then
    echo "skip $example: queued or running"
    continue
  fi

  # Only the replicates without a predicted structure yet.
  todo=()
  for n in $(expand "$replicates"); do
    compgen -G "$example/output/replicate-$n/*/*_model.cif" > /dev/null || todo+=("$n")
  done
  if (( ${#todo[@]} == 0 )); then
    echo "skip $example: all replicates done"
    continue
  fi
  # Join the remaining replicates with commas into an --array list, e.g. 2,4.
  # Array task N runs replicate N, so a retry keeps its replicate number.
  array=$(IFS=,; echo "${todo[*]}")

  # Per-example job names so reruns can see what's queued; the log names stay
  # af3-data-<jobid>_N.out and af3-inference-<jobid>_N.out as in the READMEs.
  # AF3_STAGE2=no: stage1.sh would otherwise submit stage 2 itself.
  # Stage 1 (data pipeline, CPU on RM-shared) uses the partition, cores and
  # time limit from the #SBATCH lines in stage1.sh.
  stage1=(sbatch --parsable -A "$account" --array="$array" --export=ALL,AF3_STAGE2=no
          --job-name="af3-data-$example" --output="af3-data-%A_%a.out"
          stage1.sh)
  # Stage 2 (inference on GPU-shared) overrides the GPU type from stage2.sh.
  # --kill-on-invalid-dep=yes cancels a stage 2 task whose stage 1 task failed
  # instead of leaving it pending forever. The script name is appended after
  # the dependency below, once the stage 1 job id is known.
  stage2=(sbatch --parsable -A "$account" "${reservation[@]}" --array="$array"
          --gpus="$gpu:1" --job-name="af3-inference-$example"
          --output="af3-inference-%A_%a.out" --kill-on-invalid-dep=yes)

  if $dry_run; then
    echo "(cd $example && ${stage1[*]})"
    echo "(cd $example && ${stage2[*]} --dependency=aftercorr:<stage 1 job id> stage2.sh)"
  else
    # Submit from inside the example directory so each job's
    # SLURM_SUBMIT_DIR (and with it output/ and the logs) is that example.
    # --parsable makes sbatch print just the job id.
    jobid1=$(cd "$example" && "${stage1[@]}")
    # aftercorr pairs the arrays task by task: stage 2 task N starts as soon
    # as stage 1 task N succeeds, without waiting for the other replicates.
    jobid2=$(cd "$example" && "${stage2[@]}" --dependency=aftercorr:"$jobid1" stage2.sh)
    echo "submitted $example replicates $array on $gpu: stage 1 $jobid1, stage 2 $jobid2"
  fi
done
