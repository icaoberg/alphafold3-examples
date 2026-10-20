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

# Submit every example with all its replicates: stage 1 (the data pipeline on
# RM-shared) as a job array, one task per replicate.
#
# Usage, from any directory:
#   ./submit.sh -A <allocation-id> [-r <replicates>] [-n] [example ...]
#
#   -A  allocation to charge
#   -r  replicates to run, as a Slurm --array range (default 1-5)
#   -n  dry run: print the sbatch commands without submitting
#   example ...  directories to run (default: every example*/ here)
#
# Replicates that already have data pipeline output
# (output/replicate-N/<name>/<name>_data.json) are skipped, and so are
# examples with jobs still queued or running, so the same command can be
# resubmitted to retry failed replicates.

# Abort on any failed command (-e), unset variable (-u) or failure inside a
# pipeline (-o pipefail).
set -euo pipefail

# Defaults, overridden by the command-line flags parsed below.
account=""
replicates="1-5"
dry_run=false
while getopts "A:r:n" opt; do
  case $opt in
    A) account=$OPTARG ;;
    r) replicates=$OPTARG ;;
    n) dry_run=true ;;
    *) exit 2 ;;  # getopts already printed the error for an unknown flag
  esac
done
# Drop the parsed flags so "$@" holds only the example directories.
shift $((OPTIND - 1))

# An allocation is required, and the replicates must look like a Slurm
# --array range: comma-separated numbers or N-M ranges, e.g. 1-5 or 1-3,5.
if [[ -z "$account" || ! "$replicates" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]]; then
  echo "Usage: $0 -A <allocation-id> [-r <replicates>] [-n] [example ...]" >&2
  exit 2
fi

# Work from the directory holding this script, so it can be called from
# anywhere and example paths resolve relative to this directory.
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
  # Don't double-submit: an example still in the queue is left alone until
  # its jobs finish.
  if grep -qx "af3-data-$example" <<< "$queued"; then
    echo "skip $example: queued or running"
    continue
  fi

  # Only the replicates without data pipeline output yet.
  todo=()
  for n in $(expand "$replicates"); do
    compgen -G "$example/output/replicate-$n/*/*_data.json" > /dev/null || todo+=("$n")
  done
  if (( ${#todo[@]} == 0 )); then
    echo "skip $example: all replicates done"
    continue
  fi
  # Join the remaining replicates with commas into an --array list, e.g. 2,4.
  # Array task N runs replicate N, so a retry keeps its replicate number.
  array=$(IFS=,; echo "${todo[*]}")

  # Per-example job names so reruns can see what's queued; the log names stay
  # af3-data-<jobid>_N.out as in the READMEs. Stage 1 (data pipeline, CPU on
  # RM-shared) uses the partition, cores and time limit from the #SBATCH lines
  # in stage1.sh.
  stage1=(sbatch --parsable -A "$account" --array="$array"
          --job-name="af3-data-$example" --output="af3-data-%A_%a.out"
          stage1.sh)

  if $dry_run; then
    echo "(cd $example && ${stage1[*]})"
  else
    # Submit from inside the example directory so each job's
    # SLURM_SUBMIT_DIR (and with it output/ and the logs) is that example.
    # --parsable makes sbatch print just the job id.
    jobid1=$(cd "$example" && "${stage1[@]}")
    echo "submitted $example replicates $array: stage 1 $jobid1"
  fi
done
