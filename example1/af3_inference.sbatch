#!/bin/bash
#SBATCH --job-name=af3-inference
#SBATCH --partition=GPU-shared
#SBATCH --gpus=v100-32:1
#SBATCH --ntasks-per-node=5
#SBATCH --time=02:00:00
#SBATCH --output=%x-%j.out

# Stage 2 of 2: predict the structure from the stage 1 output on one GPU.
# submit_af3.sh submits this job when stage 1 finishes and sets AF3_NAME.
# To run only this stage (for example, after an inference failure):
#   sbatch -A <allocation-id> --export=ALL,AF3_NAME=<name> af3_inference.sbatch

set -euo pipefail

: "${AF3_NAME:?Set AF3_NAME to the job name from the input JSON}"

export AF3_ROOT=/ocean/datasets/community/alphafold3
export AF3_IMAGE=${AF3_IMAGE:-/ocean/containers/alphafold3/singularity-alphafold3-v3.0.4.sif}
export AF3_MODEL_DIR=${AF3_MODEL_DIR:-$AF3_ROOT/weights}
export AF3_OUTPUT_DIR=${AF3_OUTPUT_DIR:-$PROJECT/af3_output}
export AF3_DATA_JSON=${AF3_DATA_JSON:-$AF3_OUTPUT_DIR/$AF3_NAME/${AF3_NAME}_data.json}

if [[ ! -f "$AF3_DATA_JSON" ]]; then
  echo "Missing $AF3_DATA_JSON. Run submit_af3.sh first." >&2
  exit 1
fi

# Node-local scratch and JAX cache. $LOCAL is deleted when the job ends.
export AF3_SCRATCH=${AF3_SCRATCH:-$LOCAL/af3}
export AF3_JAX_CACHE_DIR=${AF3_JAX_CACHE_DIR:-$AF3_SCRATCH/jax_cache}
mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp" "$AF3_JAX_CACHE_DIR"

# Copy results from $LOCAL to $PROJECT when the script exits, even on failure.
trap 'rsync -a "$AF3_SCRATCH/output/" "$AF3_OUTPUT_DIR/"' EXIT

export APPTAINERENV_TMPDIR="$AF3_SCRATCH/tmp"

# V100 GPUs (compute capability 7.0) need XLA attention and this XLA flag.
# L40S and H100 GPUs use the default Triton attention.
attention=triton
if nvidia-smi --query-gpu=name --format=csv,noheader | grep -q V100; then
  attention=xla
  export APPTAINERENV_XLA_FLAGS="--xla_disable_hlo_passes=custom-kernel-fusion-rewriter"
fi

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
    --flash_attention_implementation="$attention" \
    --norun_data_pipeline
