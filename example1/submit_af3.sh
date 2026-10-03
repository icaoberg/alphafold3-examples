#!/bin/bash
# Submit the data pipeline (RM-shared) and inference (GPU-shared) jobs for one
# input. Inference starts only if the data pipeline succeeds.
#
# Usage: ./submit_af3.sh <allocation-id> [input.json]
#
# The input defaults to fold_input.json in this directory.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <allocation-id> [input.json]" >&2
  exit 1
fi

account=$1
here=$(dirname "$(realpath "$0")")
export AF3_INPUT=$(realpath "${2:-$here/fold_input.json}")

# AlphaFold 3 names the output directory after the input's "name", with spaces
# replaced by underscores and characters other than [A-Za-z0-9_.-] removed.
export AF3_NAME=$(python3 -c '
import json, re, sys
name = json.load(open(sys.argv[1]))["name"].replace(" ", "_")
print(re.sub(r"[^A-Za-z0-9_.-]", "", name))
' "$AF3_INPUT")

# Slurm options for both jobs. Options given to sbatch on the command line take
# precedence over the #SBATCH lines inside the job scripts, so edit them here.

# Stage 1: data pipeline on CPUs.
data_jid=$(sbatch --parsable \
  --account="$account" \
  --job-name=af3-data \
  --partition=RM-shared \
  --ntasks-per-node=32 \
  --time=12:00:00 \
  --output=af3-data-%j.out \
  --export=ALL \
  "$here/af3_data_pipeline.sbatch")

# Stage 2: inference on one GPU. Starts only if stage 1 succeeds.
infer_jid=$(sbatch --parsable \
  --account="$account" \
  --job-name=af3-inference \
  --partition=GPU-shared \
  --gpus=v100-32:1 \
  --ntasks-per-node=5 \
  --time=02:00:00 \
  --output=af3-inference-%j.out \
  --dependency=afterok:"$data_jid" \
  --export=ALL \
  "$here/af3_inference.sbatch")

echo "Input:         $AF3_INPUT"
echo "Data pipeline: job $data_jid"
echo "Inference:     job $infer_jid (starts after $data_jid succeeds)"
echo "Results:       ${AF3_OUTPUT_DIR:-$PROJECT/af3_output}/$AF3_NAME"
