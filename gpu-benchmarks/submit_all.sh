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

# Submit one round of the stage 2 GPU benchmark: every example on every GPU
# type, one job each.
#
# Usage, from this directory:
#   ./submit_all.sh -A <allocation-id> -r <repeat> [-n] [example ...]
#
#   -A  allocation to charge
#   -r  repeat number (1, 2, 3, ...); submit the next round only after the
#       previous one finishes, so runs don't share nodes with each other
#   -n  dry run: print the sbatch commands without submitting
#   example ...  directories to run (default: every example*/ here)
#
# Set GPUS to change the GPU types, e.g. GPUS="l40s-48 h100-80".
#
# A run is skipped if it already succeeded or is still queued or running, so
# the same round can be resubmitted to retry failed runs.

set -euo pipefail

GPUS=${GPUS:-"v100-32 l40s-48 h100-80"}

account="pscstaff"
repeat="5"
dry_run=false
while getopts "A:r:n" opt; do
  case $opt in
    A) account=$OPTARG ;;
    r) repeat=$OPTARG ;;
    n) dry_run=true ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))

if [[ -z "$account" || ! "$repeat" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 -A <allocation-id> -r <repeat> [-n] [example ...]" >&2
  exit 2
fi

cd "$(dirname "$(realpath "$0")")"

if (( $# > 0 )); then
  examples=("${@%/}")
else
  examples=($(ls -d example*/ | tr -d / | sort -V))
fi

queued=$(squeue -u "$USER" -h -o %j)

for example in "${examples[@]}"; do
  for gpu in $GPUS; do
    name=af3-s2-$example-$gpu-r$repeat

    if grep -qx "$name" <<< "$queued"; then
      echo "skip $name: queued or running"
      continue
    fi
    if grep -lqs "^Done running" "$example/$name"-*.out; then
      echo "skip $name: already done"
      continue
    fi

    cmd=(sbatch --parsable -A "$account" --gpus="$gpu:1" --job-name="$name"
         --export=ALL,AF3_GPU="$gpu",AF3_REPEAT="$repeat" stage2.sh)
    if $dry_run; then
      echo "(cd $example && ${cmd[*]})"
    else
      jobid=$(cd "$example" && "${cmd[@]}")
      echo "submitted $name: $jobid"
    fi
  done
done
