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
#
#SBATCH --job-name=af3-data
#SBATCH --partition=RM-shared
#SBATCH --ntasks-per-node=32
#SBATCH --time=12:00:00
#SBATCH --array=1-5
#SBATCH --output=%x-%A_%a.out

# Stage 1 of 2: build MSAs and find templates on RM-shared (CPU only).
# Stage 2 (stage2.sh) runs inference on GPU-shared.
#
# Usage, from this directory:
#   sbatch -A <allocation-id> stage1.sh [input.json]
#
# The input defaults to fold_input.json in the directory you submit from.
#
# When it starts, the first array task submits stage2.sh with the same input,
# account and --array, depending on this job with --dependency=aftercorr and
# --kill-on-invalid-dep=yes, so one sbatch runs both stages. Set RESERVATION to
# submit stage 2 to a reservation, or AF3_STAGE2=no to submit stage 2 yourself.
#
# Both stages are Slurm job arrays with 5 tasks, one per replicate, for
# averaging running times. Replicate N writes to output/replicate-N/, and
# --dependency=aftercorr starts stage 2 task N when stage 1 task N succeeds.
# Each replicate runs the full data pipeline. Submit with --array=1 for a
# single run.
#
# RM-shared (Bridges-2 User Guide): 2 GB of memory per core requested, up to
# 64 cores on one node, 1-hour default and 72-hour maximum time limit. The 32
# cores requested above give the MSA search tools about 64 GB of memory.

# Print how long the script took when it exits, even on failure.
SECONDS=0
print_elapsed() {
  printf 'Elapsed time: %02d:%02d:%02d\n' \
    $((SECONDS / 3600)) $((SECONDS % 3600 / 60)) $((SECONDS % 60))
}
trap print_elapsed EXIT

# Submit stage 2 once, from the first array task, before the AF3_* variables
# below are set so they don't leak into its environment. Stage 2 task N starts
# when stage 1 task N succeeds, and Slurm cancels it if that task fails. Use a
# range for --array (1-5, 1-5:2, 3); stage 2 gets min-max:step of it.
if [[ ${AF3_STAGE2:-yes} != no && -n ${SLURM_JOB_ID:-} &&
      ${SLURM_ARRAY_TASK_ID:-} == "${SLURM_ARRAY_TASK_MIN:-}" ]]; then
  if [[ -n ${SLURM_ARRAY_JOB_ID:-} ]]; then
    stage2_deps=(--array="$SLURM_ARRAY_TASK_MIN-$SLURM_ARRAY_TASK_MAX:${SLURM_ARRAY_TASK_STEP:-1}"
                 --dependency=aftercorr:"$SLURM_ARRAY_JOB_ID")
  else
    stage2_deps=(--array=1 --dependency=afterok:"$SLURM_JOB_ID")
  fi
  (cd "$SLURM_SUBMIT_DIR" &&
     sbatch -A "$SLURM_JOB_ACCOUNT" ${RESERVATION:+--reservation="$RESERVATION"} \
       "${stage2_deps[@]}" --kill-on-invalid-dep=yes stage2.sh "$@") ||
    echo "Warning: could not submit stage2.sh; submit it yourself." >&2
fi

# Load the AlphaFold 3 module. It sets AF3_IMAGE, AF3_DATABASES and
# AF3_WEIGHTS, and defines run_alphafold, which runs run_alphafold.py in the
# container with /ocean, $PROJECT and $LOCAL bound (and --nv on GPU nodes).
module load alphafold3/3.0.4 || exit 1

# Results go to output/replicate-N/ in the directory the job was submitted
# from (the example directory), where stage 2 reads the stage 1 output. N is
# the array task ID (1 when the script isn't run as an array). If you set
# AF3_OUTPUT_DIR, replicate-N/ is created inside it.
export AF3_REPLICATE=${SLURM_ARRAY_TASK_ID:-1}
export AF3_OUTPUT_DIR=${AF3_OUTPUT_DIR:-$SLURM_SUBMIT_DIR/output}/replicate-$AF3_REPLICATE
mkdir -p "$AF3_OUTPUT_DIR"

# Slurm runs a copy of this script, so find files relative to the directory
# the job was submitted from.
export AF3_INPUT=$(realpath "${1:-$SLURM_SUBMIT_DIR/fold_input.json}")

# AlphaFold 3 names the output directory after the input's "name", with spaces
# replaced by underscores and characters other than [A-Za-z0-9_.-] removed.
export AF3_NAME=$(apptainer exec "$AF3_IMAGE" python3 -c '
import json, re, sys
name = json.load(open(sys.argv[1]))["name"].replace(" ", "_")
print(re.sub(r"[^A-Za-z0-9_.-]", "", name))
' "$AF3_INPUT")

data_json="$AF3_OUTPUT_DIR/$AF3_NAME/${AF3_NAME}_data.json"

echo "Replicate: $AF3_REPLICATE"
echo "Input:  $AF3_INPUT"
echo "Output: $AF3_OUTPUT_DIR/$AF3_NAME"

# Skip the data pipeline if an earlier job already finished it.
if [[ -f "$data_json" ]]; then
  echo "Found $data_json; skipping the data pipeline."
else
  # Node-local scratch. $LOCAL is deleted when the job ends.
  export AF3_SCRATCH=${AF3_SCRATCH:-$LOCAL/af3}
  mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp"

  # Copy results from $LOCAL to $AF3_OUTPUT_DIR when the script exits, even on failure.
  trap 'rsync -a "$AF3_SCRATCH/output/" "$AF3_OUTPUT_DIR/"; print_elapsed' EXIT

  # Send temporary files from the MSA tools to $LOCAL instead of /tmp.
  export APPTAINERENV_TMPDIR="$AF3_SCRATCH/tmp"

  run_alphafold \
    --json_path="$AF3_INPUT" \
    --db_dir="$AF3_DATABASES" \
    --output_dir="$AF3_SCRATCH/output" \
    --jackhmmer_n_cpu=8 \
    --nhmmer_n_cpu=8 \
    --norun_inference
fi
