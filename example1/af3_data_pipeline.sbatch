#!/bin/bash
#SBATCH --job-name=af3-data
#SBATCH --partition=RM-shared
#SBATCH --ntasks-per-node=32
#SBATCH --time=12:00:00
#SBATCH --output=%x-%j.out

# Stage 1: build MSAs and find templates (CPU only).
# Submit with submit_af3.sh, which sets AF3_INPUT and AF3_NAME.
# submit_af3.sh passes its own Slurm options, which take precedence over the
# #SBATCH lines above. These lines apply when you run sbatch on this file directly.

set -euo pipefail

: "${AF3_INPUT:?Set AF3_INPUT to the input JSON file}"
: "${AF3_NAME:?Set AF3_NAME to the job name from the input JSON}"

export AF3_ROOT=/ocean/datasets/community/alphafold3
export AF3_IMAGE=${AF3_IMAGE:-/ocean/containers/alphafold3/singularity-alphafold3-v3.0.4.sif}
export AF3_DB_DIR=${AF3_DB_DIR:-$AF3_ROOT/databases}
export AF3_OUTPUT_DIR=${AF3_OUTPUT_DIR:-$PROJECT/af3_output}
mkdir -p "$AF3_OUTPUT_DIR"

# Skip the data pipeline if an earlier job already finished it.
if [[ -f "$AF3_OUTPUT_DIR/$AF3_NAME/${AF3_NAME}_data.json" ]]; then
  echo "Found $AF3_OUTPUT_DIR/$AF3_NAME/${AF3_NAME}_data.json; skipping the data pipeline."
  exit 0
fi

# Node-local scratch. $LOCAL is deleted when the job ends.
export AF3_SCRATCH=${AF3_SCRATCH:-$LOCAL/af3}
mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp"

# Copy results from $LOCAL to $PROJECT when the script exits, even on failure.
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
