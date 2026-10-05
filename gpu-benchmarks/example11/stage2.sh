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
#SBATCH --job-name=af3-stage2
#SBATCH --partition=GPU-shared
#SBATCH --gpus=l40s-48:1
#SBATCH --ntasks-per-node=5
#SBATCH --time=00:30:00
#SBATCH --output=%x-%j.out

# Stage 2 of 2, GPU benchmark version: predict the structure from the stage 1
# output on one GPU and log the timings for ../collect_results.py.
#
# Usually submitted by ../submit_all.sh, which sets the GPU type, job name and
# repeat number. To submit one run by hand, from this directory:
#   AF3_GPU=h100-80 AF3_REPEAT=1 sbatch -A <allocation-id> \
#     --gpus=h100-80:1 --job-name=af3-s2-example1-h100-80-r1 stage2.sh
#
# Results go to output/stage2/<gpu>/r<repeat>/, so runs on different GPUs and
# repeats don't overwrite each other or the stage 1 output.

set -euo pipefail

# Print how long the script took when it exits, even on failure.
SECONDS=0
print_elapsed() {
  printf 'Elapsed time: %02d:%02d:%02d\n' \
    $((SECONDS / 3600)) $((SECONDS % 3600 / 60)) $((SECONDS % 60))
  echo "Elapsed seconds: $SECONDS"
}
trap print_elapsed EXIT

export AF3_ROOT=/ocean/datasets/community/alphafold3
export AF3_IMAGE=${AF3_IMAGE:-/ocean/containers/alphafold3/singularity-alphafold3-v3.0.4.sif}
export AF3_MODEL_DIR=${AF3_MODEL_DIR:-$AF3_ROOT/weights}
# Stage 1 wrote its output to output/ in the example directory.
export AF3_OUTPUT_DIR=${AF3_OUTPUT_DIR:-$SLURM_SUBMIT_DIR/output}

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

# The GPU Slurm gave us, as reported by the driver.
AF3_GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
AF3_GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -n 1)
# Label for the results directory and the log, e.g. v100-32 or h100-80.
export AF3_GPU=${AF3_GPU:-$(echo "$AF3_GPU_NAME" | tr '[:upper:] ' '[:lower:]-')}
export AF3_REPEAT=${AF3_REPEAT:-1}

# V100s (compute capability 7.0) can't run the Triton or cuDNN attention
# kernels, and AlphaFold 3 refuses to run on them without an XLA workaround
# for a known numerical issue. Keep the image's XLA_FLAGS and add the
# workaround. See docs/performance.md in the AlphaFold 3 repository.
AF3_ATTENTION=triton
if [[ "$AF3_GPU_NAME" == *V100* ]]; then
  AF3_ATTENTION=xla
  export APPTAINERENV_XLA_FLAGS="--xla_gpu_enable_triton_gemm=false --xla_disable_hlo_passes=custom-kernel-fusion-rewriter"
fi

# Machine-readable header for ../collect_results.py.
echo "Benchmark example: $(basename "$SLURM_SUBMIT_DIR")"
echo "Benchmark gpu: $AF3_GPU"
echo "Benchmark gpu name: $AF3_GPU_NAME"
echo "Benchmark gpu memory: $AF3_GPU_MEMORY"
echo "Benchmark repeat: $AF3_REPEAT"
echo "Benchmark attention: $AF3_ATTENTION"
echo "Benchmark node: $(hostname -s)"
echo "Benchmark job id: ${SLURM_JOB_ID:-none}"
echo "Benchmark start: $(date -Is)"

export AF3_RESULTS_DIR=$AF3_OUTPUT_DIR/stage2/$AF3_GPU/r$AF3_REPEAT
mkdir -p "$AF3_RESULTS_DIR"

# Node-local scratch and JAX cache. $LOCAL is deleted when the job ends, so
# every run compiles the model from scratch and the timings are comparable.
export AF3_SCRATCH=${AF3_SCRATCH:-$LOCAL/af3}
export AF3_JAX_CACHE_DIR=${AF3_JAX_CACHE_DIR:-$AF3_SCRATCH/jax_cache}
mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp" "$AF3_JAX_CACHE_DIR"

# Copy results from $LOCAL to $AF3_RESULTS_DIR when the script exits, even on failure.
trap 'rsync -a "$AF3_SCRATCH/output/" "$AF3_RESULTS_DIR/"; print_elapsed' EXIT

export APPTAINERENV_TMPDIR="$AF3_SCRATCH/tmp"

apptainer exec --nv \
  --bind /ocean \
  --bind "$PROJECT" \
  --bind "$LOCAL" \
  "$AF3_IMAGE" \
  python /app/alphafold/run_alphafold.py \
    --json_path="$AF3_DATA_JSON" \
    --model_dir="$AF3_MODEL_DIR" \
    --output_dir="$AF3_SCRATCH/output" \
    --jax_compilation_cache_dir="$AF3_JAX_CACHE_DIR" \
    --flash_attention_implementation="$AF3_ATTENTION" \
    --norun_data_pipeline
