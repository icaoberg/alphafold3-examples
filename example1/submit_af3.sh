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

data_jid=$(sbatch --parsable -A "$account" --export=ALL "$here/af3_data_pipeline.sbatch")
infer_jid=$(sbatch --parsable -A "$account" --export=ALL \
  --dependency=afterok:"$data_jid" "$here/af3_inference.sbatch")

echo "Input:         $AF3_INPUT"
echo "Data pipeline: job $data_jid"
echo "Inference:     job $infer_jid (starts after $data_jid succeeds)"
echo "Results:       ${AF3_OUTPUT_DIR:-$PROJECT/af3_output}/$AF3_NAME"
