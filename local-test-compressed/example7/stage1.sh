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
#SBATCH --job-name=af3-data
#SBATCH --partition=RM-shared
#SBATCH --ntasks-per-node=32
#SBATCH --time=12:00:00
#SBATCH --array=1-5
#SBATCH --output=%x-%A_%a.out

# Build MSAs and find templates on RM-shared (CPU only). This runs only the
# AlphaFold 3 data pipeline (--norun_inference); it doesn't predict structures.
#
# Usage, from this directory:
#   sbatch -A <allocation-id> stage1.sh [input.json]
#
# The input defaults to fold_input.json in the directory you submit from.
#
# This is a Slurm job array with 5 tasks, one per replicate, for averaging
# running times. Replicate N writes to output/replicate-N/. Each replicate runs
# the full data pipeline. Submit with --array=1 for a single run.
#
# RM-shared (Bridges-2 User Guide): 2 GB of memory per core requested, up to
# 64 cores on one node, 1-hour default and 72-hour maximum time limit. The 32
# cores requested above give the MSA search tools about 64 GB of memory.
#
# Before running AlphaFold 3, the job copies the databases the input needs
# from $AF3_DATABASES on Ocean to node-local storage ($LOCAL) and points
# AF3_DATABASES at the copy, so the MSA and template searches read from
# local disk. The log records how long the copy and AlphaFold 3 each took:
#   Copied <database> (<size>) in <seconds> seconds
#   Extracted mmcif_files.tgz (<size>) in <seconds> seconds
#   Database copy seconds: <seconds>
#   AlphaFold 3 seconds: <seconds>
# mmcif_files is many small files, so instead of copying the directory the
# job copies $AF3_DATABASES/mmcif_files.tgz and extracts it on $LOCAL (the
# tarball is deleted afterwards). Database copy seconds includes the
# extraction.
# Protein chains need about 580 GB (the five protein databases and
# mmcif_files, plus room for the tarball while it is extracted) and RNA chains
# about 95 GB, so check that $LOCAL has room.

# Print how long the script took when it exits, even on failure.
SECONDS=0
print_elapsed() {
  printf 'Elapsed time: %02d:%02d:%02d\n' \
    $((SECONDS / 3600)) $((SECONDS % 3600 / 60)) $((SECONDS % 60))
}
trap print_elapsed EXIT

# Load the AlphaFold 3 module. It sets AF3_IMAGE, AF3_DATABASES and
# AF3_WEIGHTS, and defines run_alphafold, which runs run_alphafold.py in the
# container with /ocean, $PROJECT and $LOCAL bound (and --nv on GPU nodes).
module load alphafold3/3.0.4 || exit 1

# Results go to output/replicate-N/ in the directory the job was submitted
# from (the example directory). N is the array task ID (1 when the script
# isn't run as an array). If you set AF3_OUTPUT_DIR, replicate-N/ is created
# inside it.
export AF3_REPLICATE=${SLURM_ARRAY_TASK_ID:-1}
export AF3_OUTPUT_DIR=${AF3_OUTPUT_DIR:-$SLURM_SUBMIT_DIR/output}/replicate-$AF3_REPLICATE
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

echo "Replicate: $AF3_REPLICATE"
echo "Input:  $AF3_INPUT"
echo "Output: $AF3_OUTPUT_DIR/$AF3_NAME"

# Skip the data pipeline if an earlier job already finished it.
if [[ -f "$data_json" ]]; then
  echo "Found $data_json; skipping the data pipeline."
else
  # Node-local scratch. $LOCAL is deleted when the job ends.
  export AF3_SCRATCH=${AF3_SCRATCH:-$LOCAL/af3}
  mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp"

  # Copy results from $LOCAL to $AF3_OUTPUT_DIR when the script exits, even on failure.
  trap 'rsync -a "$AF3_SCRATCH/output/" "$AF3_OUTPUT_DIR/"; print_elapsed' EXIT

  # Send temporary files from the MSA tools to $LOCAL instead of /tmp.
  export APPTAINERENV_TMPDIR="$AF3_SCRATCH/tmp"

  # The databases each chain type is searched against. DNA chains and
  # ligands aren't searched.
  protein_dbs=(uniref90_2022_05.fa mgy_clusters_2022_05.fa
               bfd-first_non_consensus_sequences.fasta uniprot_all_2021_04.fa
               pdb_seqres_2022_09_28.fasta mmcif_files)
  rna_dbs=(rfam_14_9_clust_seq_id_90_cov_80_rep_seq.fasta
           rnacentral_active_seq_id_90_cov_80_linclust.fasta
           nt_rna_2023_02_23_clust_seq_id_90_cov_80_rep_seq.fasta)

  # Chain types in the input, e.g. "protein rna".
  chain_types=$(apptainer exec "$AF3_IMAGE" python3 -c '
import json, sys
seqs = json.load(open(sys.argv[1]))["sequences"]
print(" ".join(sorted({k for s in seqs for k in s})))
' "$AF3_INPUT")
  dbs=()
  [[ " $chain_types " == *" protein "* ]] && dbs+=("${protein_dbs[@]}")
  [[ " $chain_types " == *" rna "* ]] && dbs+=("${rna_dbs[@]}")

  # Copy the databases to $LOCAL, timing each one and the whole copy.
  ocean_databases=$AF3_DATABASES
  export AF3_DATABASES="$AF3_SCRATCH/databases"
  mkdir -p "$AF3_DATABASES"
  echo "Chain types: $chain_types"
  echo "Copying ${#dbs[@]} database(s) from $ocean_databases to $AF3_DATABASES"
  copy_start=$SECONDS
  for db in "${dbs[@]}"; do
    # Copy mmcif_files as one tarball, then extract it on $LOCAL.
    src=$db
    [[ $db == mmcif_files ]] && src=mmcif_files.tgz
    start=$(date +%s.%N)
    cp -r "$ocean_databases/$src" "$AF3_DATABASES/" || exit 1
    end=$(date +%s.%N)
    size=$(du -sh --apparent-size "$AF3_DATABASES/$src" | cut -f1)
    printf 'Copied %s (%s) in %.1f seconds\n' "$src" "$size" \
      "$(echo "$end - $start" | bc)"
    if [[ $src == mmcif_files.tgz ]]; then
      start=$(date +%s.%N)
      tar -xzf "$AF3_DATABASES/$src" -C "$AF3_DATABASES" || exit 1
      rm "$AF3_DATABASES/$src"
      [[ -d "$AF3_DATABASES/mmcif_files" ]] || {
        echo "$src didn't extract to $AF3_DATABASES/mmcif_files" >&2; exit 1; }
      end=$(date +%s.%N)
      size=$(du -sh --apparent-size "$AF3_DATABASES/mmcif_files" | cut -f1)
      printf 'Extracted %s (%s) in %.1f seconds\n' "$src" "$size" \
        "$(echo "$end - $start" | bc)"
    fi
  done
  echo "Database copy seconds: $((SECONDS - copy_start))"
  df -h "$AF3_DATABASES"

  # Databases the input doesn't need aren't copied; --db_dir falls back to
  # Ocean for them because AlphaFold 3 checks that every database exists.
  # They are never searched.
  af3_start=$SECONDS
  run_alphafold \
    --json_path="$AF3_INPUT" \
    --db_dir="$AF3_DATABASES" \
    --db_dir="$ocean_databases" \
    --output_dir="$AF3_SCRATCH/output" \
    --jackhmmer_n_cpu=8 \
    --nhmmer_n_cpu=8 \
    --norun_inference
  echo "AlphaFold 3 seconds: $((SECONDS - af3_start))"
fi
