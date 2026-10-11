#!/bin/bash
#SBATCH --job-name=af3-foldbench-data
#SBATCH --partition=RM-shared
#SBATCH --ntasks-per-node=32
#SBATCH --time=12:00:00
#SBATCH --output=%x-%A_%a.out

# Stage 1 of 2: search the AlphaFold 3 genetic databases (MSAs and templates)
# for FoldBench targets on RM-shared (CPU only). Stage 2 (stage2.sh) runs
# inference on GPU-shared. Adapted from ../../../vanilla-examples/*/stage1.sh.
#
# Each array task handles one target: task N takes the Nth entry of the
# FoldBench input list (examples/alphafold3_inputs.json by default). Submit
# from the FoldBench root with one task per target:
#
#   N=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' \
#         examples/alphafold3_inputs.json)
#   sbatch -A <allocation-id> --array=1-$N algorithms/AlphaFold3/stage1.sh [inputs.json]
#
# Add a throttle (e.g. --array=1-$N%50) to limit how many run at once.
#
# When it starts, the first array task submits stage2.sh with the same input,
# account and array range, depending on this job with --dependency=aftercorr,
# so stage 2 task N starts when stage 1 task N succeeds. Set AF3_STAGE2=no to
# submit stage 2 yourself, RESERVATION to submit it to a reservation, and
# AF3_GPUS to change its GPU request (default l40s-48:1).
#
# Outputs follow FoldBench's layout, so postprocess.py and evaluate.py find them:
#   examples/outputs/input/AlphaFold3/<name>.json                       one input per target
#   examples/outputs/prediction/AlphaFold3/<name>/<name>_data.json      stage 1 result
#
# RM-shared (Bridges-2 User Guide): 2 GB of memory per core requested, up to
# 64 cores on one node, 72-hour maximum time limit. The 32 cores requested
# above give the MSA search tools about 64 GB of memory.

# Print how long the script took when it exits, even on failure.
SECONDS=0
print_elapsed() {
  printf 'Elapsed time: %02d:%02d:%02d\n' \
    $((SECONDS / 3600)) $((SECONDS % 3600 / 60)) $((SECONDS % 60))
}
trap print_elapsed EXIT

if [[ -z ${SLURM_ARRAY_TASK_ID:-} ]]; then
  echo "Submit stage1.sh as a job array with one task per target, e.g." >&2
  echo "  sbatch -A <allocation-id> --array=1-<number of targets> $0" >&2
  exit 1
fi

# Submit stage 2 once, from the first array task, before the AF3_* variables
# below are set so they don't leak into its environment.
if [[ ${AF3_STAGE2:-yes} != no && ${SLURM_ARRAY_TASK_ID} == "${SLURM_ARRAY_TASK_MIN:-}" ]]; then
  (cd "$SLURM_SUBMIT_DIR" &&
     sbatch -A "$SLURM_JOB_ACCOUNT" ${RESERVATION:+--reservation="$RESERVATION"} \
       ${AF3_GPUS:+--gpus="$AF3_GPUS"} \
       --array="$SLURM_ARRAY_TASK_MIN-$SLURM_ARRAY_TASK_MAX:${SLURM_ARRAY_TASK_STEP:-1}" \
       --dependency=aftercorr:"$SLURM_ARRAY_JOB_ID" --kill-on-invalid-dep=yes \
       algorithms/AlphaFold3/stage2.sh "$@") ||
    echo "Warning: could not submit stage2.sh; submit it yourself." >&2
fi

# Load the AlphaFold 3 module. It sets AF3_IMAGE, AF3_DATABASES and
# AF3_WEIGHTS, and defines run_alphafold, which runs run_alphafold.py in the
# container with /ocean, $PROJECT and $LOCAL bound (and --nv on GPU nodes).
module load alphafold3/3.0.4 || exit 1

# Slurm runs a copy of this script, so find files relative to the directory
# the job was submitted from (the FoldBench root).
export AF3_INPUT=$(realpath "${1:-$SLURM_SUBMIT_DIR/examples/alphafold3_inputs.json}")
input_dir=$SLURM_SUBMIT_DIR/examples/outputs/input/AlphaFold3
prediction_dir=$SLURM_SUBMIT_DIR/examples/outputs/prediction/AlphaFold3
mkdir -p "$input_dir" "$prediction_dir"

# Write this task's target to its own input file and print its name. Each task
# writes a different file, so the array tasks don't race. FoldBench names
# (e.g. 8tuz-assembly1) are already valid AF3 output directory names.
export AF3_NAME=$(apptainer exec --bind "$(dirname "$AF3_INPUT")","$input_dir" "$AF3_IMAGE" python3 -c '
import json, sys
target = json.load(open(sys.argv[1]))[int(sys.argv[2]) - 1]
name = target["name"]
json.dump(target, open(f"{sys.argv[3]}/{name}.json", "w"), indent=4)
print(name)
' "$AF3_INPUT" "$SLURM_ARRAY_TASK_ID" "$input_dir") || exit 1

target_json="$input_dir/$AF3_NAME.json"
data_json="$prediction_dir/$AF3_NAME/${AF3_NAME}_data.json"

echo "Task:   $SLURM_ARRAY_TASK_ID"
echo "Target: $AF3_NAME"
echo "Input:  $target_json"
echo "Output: $prediction_dir/$AF3_NAME"

# Skip the data pipeline if an earlier job already finished it.
if [[ -f "$data_json" ]]; then
  echo "Found $data_json; skipping the data pipeline."
  exit 0
fi

# Node-local scratch. $LOCAL is deleted when the job ends.
export AF3_SCRATCH=${AF3_SCRATCH:-$LOCAL/af3}
mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp"

# Copy results from $LOCAL to the prediction dir when the script exits, even on failure.
trap 'rsync -a "$AF3_SCRATCH/output/" "$prediction_dir/"; print_elapsed' EXIT

# Send temporary files from the MSA tools to $LOCAL instead of /tmp.
export APPTAINERENV_TMPDIR="$AF3_SCRATCH/tmp"

run_alphafold \
  --json_path="$target_json" \
  --db_dir="$AF3_DATABASES" \
  --output_dir="$AF3_SCRATCH/output" \
  --jackhmmer_n_cpu=8 \
  --nhmmer_n_cpu=8 \
  --norun_inference
