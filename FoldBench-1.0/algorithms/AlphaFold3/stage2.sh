#!/bin/bash
#SBATCH --job-name=af3-foldbench-inference
#SBATCH --partition=GPU-shared
#SBATCH --gpus=l40s-48:1
#SBATCH --ntasks-per-node=5
#SBATCH --time=08:00:00
#SBATCH --output=%x-%A_%a.out

# Stage 2 of 2: predict FoldBench target structures from the stage 1 output on
# one GPU. Adapted from ../../../vanilla-examples/*/stage2.sh.
#
# stage1.sh submits this script itself, depending on the stage 1 job. To run
# it on its own, from the FoldBench root, after stage1.sh finishes, use the
# same input and --array as stage 1:
#   sbatch -A <allocation-id> --array=1-<number of targets> algorithms/AlphaFold3/stage2.sh [inputs.json]
#
# Task N predicts the Nth target. Each input carries 5 modelSeeds, and AF3
# makes 5 diffusion samples per seed, so each task writes 25 models under
# examples/outputs/prediction/AlphaFold3/<name>/.
#
# The time limit allows for the 5 seeds of large complexes. The largest
# FoldBench assemblies may need more GPU memory than an L40S has; rerun those
# tasks with e.g. AF3_GPUS=h100-80:1 or sbatch --gpus=h100-80:1.
#
# When all tasks have finished, write prediction_reference.csv and score,
# from the FoldBench root:
#   python algorithms/AlphaFold3/postprocess.py \
#     --input_dir examples/outputs/input/AlphaFold3 \
#     --prediction_dir examples/outputs/prediction/AlphaFold3 \
#     --evaluation_dir examples/outputs/evaluation/AlphaFold3
#   python evaluate.py --algorithm_name AlphaFold3
#   python task_score_summary.py --algorithm_names AlphaFold3

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

if [[ -z ${SLURM_ARRAY_TASK_ID:-} ]]; then
  echo "Submit stage2.sh as a job array with the same --array as stage1.sh." >&2
  exit 1
fi

# Slurm runs a copy of this script, so find files relative to the directory
# the job was submitted from (the FoldBench root).
export AF3_INPUT=$(realpath "${1:-$SLURM_SUBMIT_DIR/examples/alphafold3_inputs.json}")
prediction_dir=$SLURM_SUBMIT_DIR/examples/outputs/prediction/AlphaFold3

# Name of this task's target, the Nth entry of the input list as in stage 1.
export AF3_NAME=$(apptainer exec --bind "$(dirname "$AF3_INPUT")" "$AF3_IMAGE" python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))[int(sys.argv[2]) - 1]["name"])
' "$AF3_INPUT" "$SLURM_ARRAY_TASK_ID")

data_json="$prediction_dir/$AF3_NAME/${AF3_NAME}_data.json"

echo "Task:   $SLURM_ARRAY_TASK_ID"
echo "Target: $AF3_NAME"
echo "Input:  $data_json"
echo "Output: $prediction_dir/$AF3_NAME"

if [[ ! -f "$data_json" ]]; then
  echo "Missing $data_json. Run stage1.sh first." >&2
  exit 1
fi

# Skip inference if an earlier job already finished it, so rerunning the
# array retries only failed targets.
if [[ -f "$prediction_dir/$AF3_NAME/${AF3_NAME}_ranking_scores.csv" ]]; then
  echo "Found ${AF3_NAME}_ranking_scores.csv; skipping inference."
  exit 0
fi

# Node-local scratch and JAX cache. $LOCAL is deleted when the job ends.
# Writing to an empty scratch dir also keeps AF3 from renaming its output dir,
# which it does when <name>/ already exists (it does: stage 1 wrote there).
export AF3_SCRATCH=${AF3_SCRATCH:-$LOCAL/af3}
export AF3_JAX_CACHE_DIR=${AF3_JAX_CACHE_DIR:-$AF3_SCRATCH/jax_cache}
mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp" "$AF3_JAX_CACHE_DIR"

# Copy results from $LOCAL to the prediction dir when the script exits, even on failure.
trap 'rsync -a "$AF3_SCRATCH/output/" "$prediction_dir/"; print_elapsed' EXIT

export APPTAINERENV_TMPDIR="$AF3_SCRATCH/tmp"

run_alphafold \
  --json_path="$data_json" \
  --model_dir="$AF3_WEIGHTS" \
  --output_dir="$AF3_SCRATCH/output" \
  --jax_compilation_cache_dir="$AF3_JAX_CACHE_DIR" \
  --num_diffusion_samples=5 \
  --norun_data_pipeline
