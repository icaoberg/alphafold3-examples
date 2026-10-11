#!/bin/bash
# RECONSTRUCTION: FoldBench does not ship its AlphaFold 3 integration. This
# script is inferred from the Protenix make_predictions.sh and the inputs in
# examples/alphafold3_inputs.json. It has not been run.

af3_input_json=$1
input_dir=$2
prediction_dir=$3
evaluation_dir=$4
gpu_id=$5

PYTHON_PATH="python"
# Genetic databases and model weights live outside the container. The
# alphafold3 module on Bridges-2 sets AF3_DATABASES and AF3_WEIGHTS, and
# Apptainer passes them through; run.sh must also bind their directory
# (e.g. -B /ocean).
db_dir=${AF3_DATABASES:-/ocean/datasets/community/alphafold3/databases}
model_dir=${AF3_WEIGHTS:-/ocean/datasets/community/alphafold3/weights}

# split the benchmark input list into one AF3 input file per target
$PYTHON_PATH ./preprocess.py --af3_input_json="$af3_input_json" --input_dir="$input_dir"

# run inference

export CUDA_VISIBLE_DEVICES=$gpu_id

# Seeds come from modelSeeds in each input (42,66,101,2024,8888).
# 5 seeds x 5 diffusion samples = 25 predictions per target, as for Protenix.
N_sample=5

# The inputs leave unpairedMsa, pairedMsa and templates as null, so
# AlphaFold 3 runs its own data pipeline (MSA and template search) for each
# target before inference.
$PYTHON_PATH /app/alphafold/run_alphafold.py \
--input_dir="$input_dir" \
--output_dir="$prediction_dir" \
--db_dir="$db_dir" \
--model_dir="$model_dir" \
--num_diffusion_samples=${N_sample}

# Collect the AF3 ranking scores and model paths into
# prediction_reference.csv in evaluation_dir
$PYTHON_PATH ./postprocess.py --input_dir="$input_dir" --prediction_dir="$prediction_dir" --evaluation_dir="$evaluation_dir"
