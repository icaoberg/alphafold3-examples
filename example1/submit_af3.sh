#!/bin/bash
#SBATCH --job-name=af3-data
#SBATCH --partition=RM-shared
#SBATCH --ntasks-per-node=32
#SBATCH --time=12:00:00
#SBATCH --output=%x-%j.out

# Stage 1 of 2: build MSAs and find templates on RM-shared (CPU only), then
# submit stage 2 (af3_inference.sbatch) to GPU-shared.
#
# Usage, from this directory:
#   sbatch -A <allocation-id> submit_af3.sh [input.json]
#
# The input defaults to fold_input.json in the directory you submit from.
#
# RM-shared (Bridges-2 User Guide): 2 GB of memory per core requested, up to
# 64 cores on one node, 1-hour default and 72-hour maximum time limit. The 32
# cores requested above give the MSA search tools about 64 GB of memory.

set -euo pipefail

export AF3_ROOT=/ocean/datasets/community/alphafold3
export AF3_IMAGE=${AF3_IMAGE:-/ocean/containers/alphafold3/singularity-alphafold3-v3.0.4.sif}
export AF3_DB_DIR=${AF3_DB_DIR:-$AF3_ROOT/databases}
export AF3_OUTPUT_DIR=${AF3_OUTPUT_DIR:-$PROJECT/af3_output}
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

echo "Input:  $AF3_INPUT"
echo "Output: $AF3_OUTPUT_DIR/$AF3_NAME"

# Skip the data pipeline if an earlier job already finished it.
if [[ -f "$data_json" ]]; then
  echo "Found $data_json; skipping the data pipeline."
else
  # Node-local scratch. $LOCAL is deleted when the job ends.
  export AF3_SCRATCH=${AF3_SCRATCH:-$LOCAL/af3}
  mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp"

  # If the data pipeline fails, still copy whatever it wrote to $PROJECT.
  trap 'rsync -a "$AF3_SCRATCH/output/" "$AF3_OUTPUT_DIR/"' EXIT

  # Send temporary files from the MSA tools to $LOCAL instead of /tmp.
  export APPTAINERENV_TMPDIR="$AF3_SCRATCH/tmp"

  apptainer exec \
    --bind /ocean \
    --bind "$PROJECT" \
    --bind "$LOCAL" \
    "$AF3_IMAGE" \
    python /app/alphafold/run_alphafold.py \
      --json_path="$AF3_INPUT" \
      --db_dir="$AF3_DB_DIR" \
      --output_dir="$AF3_SCRATCH/output" \
      --jackhmmer_n_cpu=8 \
      --nhmmer_n_cpu=8 \
      --norun_inference

  # Copy the results to $PROJECT now, so they're there before stage 2 starts.
  rsync -a "$AF3_SCRATCH/output/" "$AF3_OUTPUT_DIR/"
fi

# Stage 2: submit inference to GPU-shared, charged to the same allocation.
# Its Slurm options are the #SBATCH lines in af3_inference.sbatch.
sbatch \
  --account="$SLURM_JOB_ACCOUNT" \
  --export=ALL \
  "$SLURM_SUBMIT_DIR/af3_inference.sbatch"
