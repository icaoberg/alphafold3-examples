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
#SBATCH --job-name=af3-inference
#SBATCH --partition=GPU-shared
#SBATCH --gpus=l40s-48:1
#SBATCH --ntasks-per-node=5
#SBATCH --time=02:00:00
#SBATCH --array=1-5
#SBATCH --output=%x-%A_%a.out

# Stage 2 of 2: predict the structure from the stage 1 output on one GPU.
#
# stage1.sh submits this script itself, depending on the stage 1 job. To run
# it on its own, from this directory, after stage1.sh finishes:
#   sbatch -A <allocation-id> stage2.sh [input.json]
#
# Pass the same input as stage 1. It defaults to fold_input.json in the
# directory you submit from.
#
# Like stage 1, this is a job array with 5 tasks: task N predicts from
# output/replicate-N/ and writes its results there. Use the same --array as
# stage 1.

# Load the AlphaFold 3 module. It sets AF3_IMAGE, AF3_DATABASES and
# AF3_WEIGHTS, and defines run_alphafold, which runs run_alphafold.py in the
# container with /ocean, $PROJECT and $LOCAL bound (and --nv on GPU nodes).
module load alphafold3/3.0.4 || exit 1

set -euo pipefail

# Print how long the script took when it exits, even on failure.
SECONDS=0
print_elapsed() {
  printf 'Elapsed time: %02d:%02d:%02d\n' \
    $((SECONDS / 3600)) $((SECONDS % 3600 / 60)) $((SECONDS % 60))
}
trap print_elapsed EXIT

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

export AF3_DATA_JSON=${AF3_DATA_JSON:-$AF3_OUTPUT_DIR/$AF3_NAME/${AF3_NAME}_data.json}

if [[ ! -f "$AF3_DATA_JSON" ]]; then
  echo "Missing $AF3_DATA_JSON. Run stage1.sh first." >&2
  exit 1
fi

# Node-local scratch and JAX cache. $LOCAL is deleted when the job ends.
export AF3_SCRATCH=${AF3_SCRATCH:-$LOCAL/af3}
export AF3_JAX_CACHE_DIR=${AF3_JAX_CACHE_DIR:-$AF3_SCRATCH/jax_cache}
mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp" "$AF3_JAX_CACHE_DIR"

# Copy results from $LOCAL to $AF3_OUTPUT_DIR when the script exits, even on failure.
trap 'rsync -a "$AF3_SCRATCH/output/" "$AF3_OUTPUT_DIR/"; print_elapsed' EXIT

export APPTAINERENV_TMPDIR="$AF3_SCRATCH/tmp"

run_alphafold \
  --json_path="$AF3_DATA_JSON" \
  --model_dir="$AF3_WEIGHTS" \
  --output_dir="$AF3_SCRATCH/output" \
  --jax_compilation_cache_dir="$AF3_JAX_CACHE_DIR" \
  --norun_data_pipeline
