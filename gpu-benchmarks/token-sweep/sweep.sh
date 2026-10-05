#!/bin/bash
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only
#
#SBATCH --job-name=af3-sweep
#SBATCH --partition=GPU-shared
#SBATCH --gpus=l40s-48:1
#SBATCH --ntasks-per-node=5
#SBATCH --time=01:00:00
#SBATCH --output=logs/%x-%j.out

# Token-size sweep: inference only on one synthetic input (empty MSA and
# templates), on one GPU. Adapted from ../stage2.sh.
#
# Usually submitted by submit_sweep.sh. By hand:
#   AF3_GPU=l40s-48 AF3_REPEAT=1 sbatch -A <allocation-id> \
#     --job-name=af3-sweep-tokens1024-l40s-48-r1 sweep.sh inputs/tokens1024.json
#
# The input has two seeds: seed 1 includes JAX compilation (cold), seed 2
# reuses the compiled model (warm, comparable to DeepMind's compile-free
# timings).
#
# Set AF3_MEMPROFILE=1 to turn off XLA's up-front 95% GPU memory allocation and
# sample nvidia-smi every second, so the log records real peak GPU memory.
# Leave it off for the timing runs.

set -euo pipefail

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

export AF3_INPUT=$(realpath "$1")
export AF3_NAME=$(basename "$AF3_INPUT" .json)   # e.g. tokens1024
AF3_TOKENS=${AF3_NAME#tokens}

AF3_GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
AF3_GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -n 1)
export AF3_GPU=${AF3_GPU:-$(echo "$AF3_GPU_NAME" | tr '[:upper:] ' '[:lower:]-')}
export AF3_REPEAT=${AF3_REPEAT:-1}
export AF3_MEMPROFILE=${AF3_MEMPROFILE:-0}

AF3_ATTENTION=triton
if [[ "$AF3_GPU_NAME" == *V100* ]]; then
  AF3_ATTENTION=xla
  export APPTAINERENV_XLA_FLAGS="--xla_gpu_enable_triton_gemm=false --xla_disable_hlo_passes=custom-kernel-fusion-rewriter"
fi

if [[ "$AF3_MEMPROFILE" == 1 ]]; then
  export APPTAINERENV_XLA_PYTHON_CLIENT_PREALLOCATE=false
fi

# Machine-readable header for collect_sweep.py.
echo "Benchmark tokens: $AF3_TOKENS"
echo "Benchmark gpu: $AF3_GPU"
echo "Benchmark gpu name: $AF3_GPU_NAME"
echo "Benchmark gpu memory: $AF3_GPU_MEMORY"
echo "Benchmark repeat: $AF3_REPEAT"
echo "Benchmark attention: $AF3_ATTENTION"
echo "Benchmark memprofile: $AF3_MEMPROFILE"
echo "Benchmark node: $(hostname -s)"
echo "Benchmark job id: ${SLURM_JOB_ID:-none}"
echo "Benchmark start: $(date -Is)"

suffix=$AF3_GPU/r$AF3_REPEAT
[[ "$AF3_MEMPROFILE" == 1 ]] && suffix=$suffix-mem
export AF3_RESULTS_DIR=$SLURM_SUBMIT_DIR/output/$AF3_NAME/$suffix
mkdir -p "$AF3_RESULTS_DIR"

export AF3_SCRATCH=$LOCAL/af3
export AF3_JAX_CACHE_DIR=$AF3_SCRATCH/jax_cache
mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp" "$AF3_JAX_CACHE_DIR"
export APPTAINERENV_TMPDIR="$AF3_SCRATCH/tmp"

# Sample GPU memory every second in the background.
memlog=$AF3_SCRATCH/gpu_mem.log
nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -l 1 \
  > "$memlog" 2>/dev/null &
smi_pid=$!

finish() {
  kill "$smi_pid" 2>/dev/null || true
  if [[ -s "$memlog" ]]; then
    echo "Peak GPU memory MiB: $(sort -n "$memlog" | tail -n 1)"
    cp "$memlog" "$AF3_RESULTS_DIR/"
  fi
  rsync -a "$AF3_SCRATCH/output/" "$AF3_RESULTS_DIR/"
  print_elapsed
}
trap finish EXIT

apptainer exec --nv \
  --bind /ocean \
  --bind "$PROJECT" \
  --bind "$LOCAL" \
  --bind "$SLURM_SUBMIT_DIR" \
  "$AF3_IMAGE" \
  python /app/alphafold/run_alphafold.py \
    --json_path="$AF3_INPUT" \
    --model_dir="$AF3_MODEL_DIR" \
    --output_dir="$AF3_SCRATCH/output" \
    --jax_compilation_cache_dir="$AF3_JAX_CACHE_DIR" \
    --flash_attention_implementation="$AF3_ATTENTION" \
    --norun_data_pipeline
