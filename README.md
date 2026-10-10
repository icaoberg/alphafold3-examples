# AlphaFold 3 Examples on Bridges-2

Working examples for running [AlphaFold 3](https://github.com/google-deepmind/alphafold3)
on the [Bridges-2](https://www.psc.edu/resources/bridges-2/) supercomputer at the
Pittsburgh Supercomputing Center (PSC). The examples use an Apptainer container,
the shared genetic databases, and the shared model weights on Bridges-2, with
Slurm batch scripts you can copy and adapt.

> [!IMPORTANT]
> AlphaFold 3 model parameters and outputs are subject to Google DeepMind's
> [Model Parameters Terms of Use](https://github.com/google-deepmind/alphafold3/blob/main/WEIGHTS_TERMS_OF_USE.md)
> and [Output Terms of Use](https://github.com/google-deepmind/alphafold3/blob/main/OUTPUT_TERMS_OF_USE.md).
> Read both before you use the weights or publish any predictions.

## Contents

- [What is on Bridges-2](#what-is-on-bridges-2)
- [Quick start](#quick-start)
- [Environment variables](#environment-variables)
- [Input format](#input-format)
- [Running AlphaFold 3](#running-alphafold-3)
- [GPU notes for Bridges-2](#gpu-notes-for-bridges-2)
- [Outputs](#outputs)
- [Troubleshooting](#troubleshooting)
- [Citing](#citing)
- [References](#references)

## What is on Bridges-2

| Resource | Location |
| --- | --- |
| Containers | `/ocean/containers/alphafold3` |
| Databases | `/ocean/datasets/community/alphafold3/databases` |
| Weights | `/ocean/datasets/community/alphafold3/weights` |

PSC keeps a shared AlphaFold 3 installation under
`/ocean/datasets/community/alphafold3`:

| Path | Contents |
| --- | --- |
| `code/alphafold3/` | Upstream source checkout (v3.0.4 plus later commits) |
| `databases/` | Genetic and structural databases used by the data pipeline (~630 GB) |
| `weights/af3.bin.zst` | AlphaFold 3 model parameters (zstd-compressed; AF3 reads them directly) |
| `image/script.sh` | Script that pulls the Apptainer images from Docker Hub |

The `databases/` directory holds:

```
bfd-first_non_consensus_sequences.fasta
mgy_clusters_2022_05.fa
mmcif_files/
nt_rna_2023_02_23_clust_seq_id_90_cov_80_rep_seq.fasta
pdb_seqres_2022_09_28.fasta
rfam_14_9_clust_seq_id_90_cov_80_rep_seq.fasta
rnacentral_active_seq_id_90_cov_80_linclust.fasta
uniprot_all_2021_04.fa
uniref90_2022_05.fa
```

### Containers

The Apptainer images are in `/ocean/containers/alphafold3`. They're built from
the Docker Hub image [`jurgjn/alphafold3`](https://hub.docker.com/r/jurgjn/alphafold3):

| Image | AlphaFold 3 version | Size |
| --- | --- | --- |
| `singularity-alphafold3-v3.0.0.sif` | v3.0.0 | 5.3 GB |
| `singularity-alphafold3-v3.0.1.sif` | v3.0.1 | 5.3 GB |
| `singularity-alphafold3-v3.0.2.sif` | v3.0.2 | 4.1 GB |
| `singularity-alphafold3-v3.0.3.sif` | v3.0.3 | 4.1 GB |
| `singularity-alphafold3-v3.0.4.sif` | v3.0.4 (used by the examples) | 4.1 GB |

List them with:

```bash
ls /ocean/containers/alphafold3
```

You don't need to download the containers, databases, or weights yourself.

## Quick start

1. Log in to Bridges-2 and clone this repository into your project space:

   ```bash
   ssh <username>@bridges2.psc.edu
   cd $PROJECT
   git clone --recurse-submodules https://github.com/icaoberg/alphafold3-examples.git
   cd alphafold3-examples
   ```

   The `alphafold3/` directory is a Git submodule of the upstream
   [google-deepmind/alphafold3](https://github.com/google-deepmind/alphafold3)
   repository, pinned to `v3.0.4` to match the default container. You don't
   need it to run the examples, but it's useful for reading the source and the
   upstream docs. If you cloned without `--recurse-submodules`, run
   `git submodule update --init`.

2. Go to an example directory and submit both stages: stage 1 (data pipeline
   on `RM-shared`) and stage 2 (inference on `GPU-shared`), which waits for
   stage 1 to succeed:

   ```bash
   cd vanilla-examples/example1
   jobid=$(sbatch --parsable -A <allocation-id> stage1.sh)
   sbatch -A <allocation-id> --dependency=aftercorr:$jobid --kill-on-invalid-dep=yes stage2.sh
   ```

3. Watch the jobs with `squeue -u $USER`. Each stage is a job array of 5
   replicates, for averaging running times. Replicate N writes its results to
   `output/replicate-N/<name>/` in the example directory.

## Environment variables

### The `alphafold3` module

Both job scripts start with `module load alphafold3/3.0.4`. The module
([`modulefile.lua`](modulefile.lua)) sets the paths to the shared install and
defines `run_alphafold`, a shell function that runs `run_alphafold.py` in the
container. It binds `/ocean`, `$PROJECT` and `$LOCAL`, and adds `--nv` when
`nvidia-smi` finds a GPU, so the same command works on `RM-shared` and
`GPU-shared` nodes.

| Variable | Value on Bridges-2 | Purpose |
| --- | --- | --- |
| `AF3_VERSION` | `3.0.4` | AlphaFold 3 version of the module |
| `AF3_ROOT` | `/ocean/datasets/community/alphafold3` | Root of the shared install |
| `AF3_IMAGES` | `/ocean/containers/alphafold3` | Directory holding the containers, one per version |
| `AF3_IMAGE` | `$AF3_IMAGES/singularity-alphafold3-v3.0.4.sif` | Apptainer image to run |
| `AF3_DATABASES` | `$AF3_ROOT/databases` | Passed to `--db_dir` in stage 1 |
| `AF3_WEIGHTS` | `$AF3_ROOT/weights` | Passed to `--model_dir` in stage 2 |
| `AF3_CODE` | `$AF3_ROOT/code/alphafold3` | AlphaFold 3 source code, for reference |

You can also load the module yourself and run AlphaFold 3 from an interactive
session:

```bash
module load alphafold3/3.0.4
run_alphafold --helpfull
```

Because the scripts load the module, exporting `AF3_IMAGE` or the other module
variables before `sbatch` has no effect: the module sets them again. To use a
different AlphaFold 3 version, change the `module load` line in both scripts to
that version's module.

### Variables read by the job scripts

The job scripts also read these environment variables and fall back to the
defaults below. `sbatch` passes your environment to the job, so any of them you
export before submitting the two stages are used by both.

| Variable | Default on Bridges-2 | Purpose |
| --- | --- | --- |
| `AF3_INPUT` | *(set by both job scripts)* | Input JSON file: the script's argument, or `fold_input.json` in the submit directory |
| `AF3_NAME` | *(set by both job scripts)* | The input's `name`; used to find `<name>/<name>_data.json` |
| `AF3_OUTPUT_DIR` | `$SLURM_SUBMIT_DIR/output` | Passed to `--output_dir`; stage 2 reads the stage 1 output from here |
| `AF3_JAX_CACHE_DIR` | `$LOCAL/af3/jax_cache` | Passed to `--jax_compilation_cache_dir` |
| `AF3_SCRATCH` | `$LOCAL/af3` | Node-local scratch for temporary files and in-progress output (batch jobs only) |

For example, to write the results to a different directory:

```bash
export AF3_OUTPUT_DIR=$PROJECT/af3_output
cd vanilla-examples/example1
jobid=$(sbatch --parsable -A <allocation-id> stage1.sh)
sbatch -A <allocation-id> --dependency=aftercorr:$jobid --kill-on-invalid-dep=yes stage2.sh
```

The example scripts add a `replicate-N/` directory inside `AF3_OUTPUT_DIR`,
so this writes to `$PROJECT/af3_output/replicate-N/<name>/`.

Clone this repository under `$PROJECT`, not `$HOME`, since results are written
inside the example directories. Your home directory quota is small.

`$LOCAL` is fast disk on the compute node your job runs on. It exists only
while the job runs and is deleted when the job ends, so the job scripts use it
for scratch and the JAX compilation cache, and copies the results to
`output/` in the example directory before the job exits. Because the cache is deleted with the job, each
new job compiles the model again (usually a few minutes). To reuse compiled
models across jobs, set `AF3_JAX_CACHE_DIR=$PROJECT/.cache/af3_jax` instead.

### Variables read by JAX/XLA inside the container

These control GPU memory and compilation. The upstream container image sets
defaults for some of them.

| Variable | Upstream default | When to change it |
| --- | --- | --- |
| `XLA_FLAGS` | `--xla_gpu_enable_triton_gemm=false` | Rarely; the default works on L40S and H100 GPUs |
| `XLA_PYTHON_CLIENT_PREALLOCATE` | `true` | Set to `false` to use unified memory |
| `XLA_CLIENT_MEM_FRACTION` | `0.95` | Set to `3.2` with unified memory |
| `TF_FORCE_UNIFIED_MEMORY` | *(unset)* | Set to `true` to let large inputs spill from GPU to host memory |

> [!WARNING]
> Apptainer gives variables defined in the image priority over
> variables in your shell, so `export XLA_FLAGS=...` on the host **won't**
> override the image's value. Pass them with `--env` or the `APPTAINERENV_`
> prefix:
>
> ```bash
> apptainer exec --nv \
>   --env XLA_PYTHON_CLIENT_PREALLOCATE=false \
>   ...
> # or
> export APPTAINERENV_XLA_PYTHON_CLIENT_PREALLOCATE=false
> ```
>
> See [Environment and Metadata](https://apptainer.org/docs/user/latest/environment_and_metadata.html)
> in the Apptainer docs for the full precedence rules.

### Unified memory (large inputs or small GPUs)

For inputs larger than the GPU can hold, enable unified memory. Runs are slower
but don't fail with out-of-memory errors:

```bash
export APPTAINERENV_XLA_PYTHON_CLIENT_PREALLOCATE=false
export APPTAINERENV_TF_FORCE_UNIFIED_MEMORY=true
export APPTAINERENV_XLA_CLIENT_MEM_FRACTION=3.2
```

## Input format

AlphaFold 3 takes a JSON file that describes the molecules to fold. A minimal
protein homodimer example (`vanilla-examples/example1/fold_input.json`):

```json
{
  "name": "2PV7",
  "sequences": [
    {
      "protein": {
        "id": ["A", "B"],
        "sequence": "GMRESYANENQFGFKTINSDIHKIVIVGGYGKLGGLFARYLRASGYPISILDREDWAVAESILANADVVIVSVPINLTLETIERLKPYLTENMLLADLTSVKREPLAKMLEVHTGAVLGLHPMFGADIASMAKQVVVRCDGRFPERYEWLLEQIQIWGAKIYQTNATEHDHNMTYIQALRHFSTFANGLHLSKQPINLANLLALSSPIYRLELAMIGRLFAQDAELYADIIMDKSENLAVIETLKQTYDEALTFFENNDRQGFIDAFHKVRDWFGDYSEQFLKESRQLLQQANDLKQG"
      }
    }
  ],
  "modelSeeds": [1],
  "dialect": "alphafold3",
  "version": 1
}
```

Inputs can also contain RNA, DNA, ligands (CCD codes or SMILES), ions,
covalent bonds, and modified residues. See the upstream
[input documentation](https://github.com/google-deepmind/alphafold3/blob/main/docs/input.md)
for the full schema.

## Running AlphaFold 3

AlphaFold 3 runs in two stages:

1. **Data pipeline (CPU only).** Runs `jackhmmer`/`nhmmer` against the
   databases to build MSAs and find templates. This can take from minutes to
   hours and doesn't use a GPU.
2. **Inference (GPU).** Runs the model on the features from stage 1.

The examples run each stage as its own Slurm job, so you're charged for a GPU
only while the model runs. Stage 1 runs on `RM-shared` and stage 2 on
`GPU-shared`, each from its own script.

Each example has its own directory with everything it needs to run:

| Example | Directory | What it predicts |
| --- | --- | --- |
| 1 | [`vanilla-examples/example1/`](vanilla-examples/example1/) | Protein homodimer (PDB 2PV7) |
| 2 | [`vanilla-examples/example2/`](vanilla-examples/example2/) | Protein heterodimer (barnase–barstar) |
| 3 | [`vanilla-examples/example3/`](vanilla-examples/example3/) | Protein with ions (calmodulin + 4 Ca²⁺) |
| 4 | [`vanilla-examples/example4/`](vanilla-examples/example4/) | Phosphorylated protein (ERK2 pThr185/pTyr187) |
| 5 | [`vanilla-examples/example5/`](vanilla-examples/example5/) | Covalent ligand (KRAS G12C + sotorasib) |
| 6 | [`vanilla-examples/example6/`](vanilla-examples/example6/) | Methylated double-stranded DNA |
| 7 | [`vanilla-examples/example7/`](vanilla-examples/example7/) | Modified RNA (tRNA-like fragment) |
| 8 | [`vanilla-examples/example8/`](vanilla-examples/example8/) | Glycoprotein (RNase B + N-glycan) |
| 9 | [`vanilla-examples/example9/`](vanilla-examples/example9/) | Protein + ligand from SMILES (streptavidin–biotin) |
| 10 | [`vanilla-examples/example10/`](vanilla-examples/example10/) | Protein–DNA complex (TetR dimer + tetO) |
| 11 | [`vanilla-examples/example11/`](vanilla-examples/example11/) | Protein homodimer + ligands (TetR + tetracycline) |
| 12 | [`vanilla-examples/example12/`](vanilla-examples/example12/) | Protein homodimer (TetR) |
| 13 | [`vanilla-examples/example13/`](vanilla-examples/example13/) | Protein–RNA complex (U1A + RNA hairpin) |
| 14 | [`vanilla-examples/example14/`](vanilla-examples/example14/) | Protein monomer (ubiquitin) |

Each example directory contains the same three files:

| File | What it does |
| --- | --- |
| `fold_input.json` | The input |
| `stage1.sh` | Stage 1 job on `RM-shared`: runs the data pipeline (`--norun_inference`) |
| `stage2.sh` | Stage 2 job on `GPU-shared` (1 GPU): runs inference (`--norun_data_pipeline`) |

The scripts are the same in every example; only `fold_input.json` changes. To
fold your own input, copy an example directory and replace `fold_input.json`.

Running times and prediction confidence scores for every example are in
[`vanilla-examples/README.md`](vanilla-examples/README.md).

### Submit

From an example directory:

```bash
jobid=$(sbatch --parsable -A <allocation-id> stage1.sh)
sbatch -A <allocation-id> --dependency=aftercorr:$jobid --kill-on-invalid-dep=yes stage2.sh
```

1. `stage1.sh` runs on `RM-shared`. It reads the `name` from the
   input JSON, runs the data pipeline, and copies `<name>/<name>_data.json`
   from `$LOCAL` to `output/replicate-N/` in the example directory.
2. `stage2.sh` waits in the queue until stage 1 succeeds, then runs on
   `GPU-shared`. It reads the same input JSON to find
   `output/replicate-N/<name>/<name>_data.json` and predicts the structure.

Both scripts are Slurm job arrays (`#SBATCH --array=1-5`) that run 5
replicates of the example, so you can average the running times. N is the
array task ID. With `--dependency=aftercorr`, stage 2 task N starts as soon as
stage 1 task N succeeds. Each replicate runs the full data pipeline. To run
only once, add `--array=1` to both `sbatch` commands. The logs are
`af3-data-<jobid>_N.out` and `af3-inference-<jobid>_N.out`.

If a stage 1 task fails, `--kill-on-invalid-dep=yes` makes Slurm cancel the
matching stage 2 task, so no GPU job runs for that replicate. `--parsable` makes `sbatch` print only the job ID, which the
second command uses.

To use a different input file, pass it to both scripts:

```bash
jobid=$(sbatch --parsable -A <allocation-id> stage1.sh my_input.json)
sbatch -A <allocation-id> --dependency=aftercorr:$jobid --kill-on-invalid-dep=yes stage2.sh my_input.json
```

You can also submit the stages one at a time without `--dependency`: submit
`stage1.sh`, wait for all its tasks to finish, then submit
`stage2.sh`.

### Stage 1: data pipeline on RM-shared

`vanilla-examples/example1/stage1.sh`:

```bash
#!/bin/bash
#SBATCH --job-name=af3-data
#SBATCH --partition=RM-shared
#SBATCH --ntasks-per-node=32
#SBATCH --time=12:00:00
#SBATCH --array=1-5
#SBATCH --output=%x-%A_%a.out

# Stage 1 of 2: build MSAs and find templates on RM-shared (CPU only).
# Stage 2 (stage2.sh) runs inference on GPU-shared.
#
# Usage, from this directory, submitting stage 2 to start after this succeeds:
#   jobid=$(sbatch --parsable -A <allocation-id> stage1.sh [input.json])
#   sbatch -A <allocation-id> --dependency=aftercorr:$jobid --kill-on-invalid-dep=yes \
#     stage2.sh [input.json]
#
# The input defaults to fold_input.json in the directory you submit from.
#
# Both stages are Slurm job arrays with 5 tasks, one per replicate, for
# averaging running times. Replicate N writes to output/replicate-N/, and
# --dependency=aftercorr starts stage 2 task N when stage 1 task N succeeds.
# Each replicate runs the full data pipeline. Submit with --array=1 for a
# single run.
#
# RM-shared (Bridges-2 User Guide): 2 GB of memory per core requested, up to
# 64 cores on one node, 1-hour default and 72-hour maximum time limit. The 32
# cores requested above give the MSA search tools about 64 GB of memory.

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
# from (the example directory), where stage 2 reads the stage 1 output. N is
# the array task ID (1 when the script isn't run as an array). If you set
# AF3_OUTPUT_DIR, replicate-N/ is created inside it.
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

  run_alphafold \
    --json_path="$AF3_INPUT" \
    --db_dir="$AF3_DATABASES" \
    --output_dir="$AF3_SCRATCH/output" \
    --jackhmmer_n_cpu=8 \
    --nhmmer_n_cpu=8 \
    --norun_inference
fi
```

From the [Bridges-2 User Guide](https://www.psc.edu/resources/bridges-2/user-guide/),
`RM-shared` jobs:

- get 2 GB of memory for each core requested with `--ntasks-per-node`;
- can use up to 64 cores, on a single node;
- have a 1-hour default time limit and a 72-hour maximum.

The script asks for 32 cores, which gives the MSA search tools about 64 GB of
memory, and 12 hours. For very large inputs, raise `--ntasks-per-node` (up to
64) for more memory, and `--time` (up to `72:00:00`).

#### Stage 1 running times

Elapsed time of each example's stage 1 job on `RM-shared` (32 cores), from the
`Elapsed time:` line at the end of its `af3-data-<jobid>.out` log, fastest to
slowest. These cover the data pipeline only, not inference.

| Example | Job ID | RM-shared |
| --- | --- | --- |
| [`vanilla-examples/example6`](vanilla-examples/example6/) | 47398843 | 00:00:15 |
| [`vanilla-examples/example12`](vanilla-examples/example12/) | 47398863 | 00:13:17 |
| [`vanilla-examples/example10`](vanilla-examples/example10/) | 47398848 | 00:13:53 |
| [`vanilla-examples/example11`](vanilla-examples/example11/) | 47398849 | 00:13:53 |
| [`vanilla-examples/example1`](vanilla-examples/example1/) | 47398729 | 00:14:46 |
| [`vanilla-examples/example3`](vanilla-examples/example3/) | 47398840 | 00:15:16 |
| [`vanilla-examples/example5`](vanilla-examples/example5/) | 47398842 | 00:16:10 |
| [`vanilla-examples/example14`](vanilla-examples/example14/) | 47398865 | 00:16:59 |
| [`vanilla-examples/example4`](vanilla-examples/example4/) | 47398841 | 00:33:29 |
| [`vanilla-examples/example9`](vanilla-examples/example9/) | 47398847 | 01:04:18 |
| [`vanilla-examples/example7`](vanilla-examples/example7/) | 47398844 | 01:13:41 |
| [`vanilla-examples/example13`](vanilla-examples/example13/) | 47398864 | 01:28:26 |
| [`vanilla-examples/example8`](vanilla-examples/example8/) | 47398845 | 01:31:54 |
| [`vanilla-examples/example2`](vanilla-examples/example2/) | 47398731 | 01:57:39 |
| **Total** | | **09:33:56** |

### Stage 2: inference on GPU-shared

`vanilla-examples/example1/stage2.sh`:

```bash
#!/bin/bash
#SBATCH --job-name=af3-inference
#SBATCH --partition=GPU-shared
#SBATCH --gpus=l40s-48:1
#SBATCH --ntasks-per-node=5
#SBATCH --time=02:00:00
#SBATCH --array=1-5
#SBATCH --output=%x-%A_%a.out

# Stage 2 of 2: predict the structure from the stage 1 output on one GPU.
#
# Usage, from this directory, after stage1.sh finishes (or with
# --dependency=aftercorr:<stage 1 job id>, see stage1.sh):
#   sbatch -A <allocation-id> stage2.sh [input.json]
#
# Pass the same input as stage 1. It defaults to fold_input.json in the
# directory you submit from.
#
# Like stage 1, this is a job array with 5 tasks: task N predicts from
# output/replicate-N/ and writes its results there. Use the same --array as
# stage 1.

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

# Results go to output/replicate-N/ in the directory the job was submitted
# from (the example directory), where stage 2 reads the stage 1 output. N is
# the array task ID (1 when the script isn't run as an array). If you set
# AF3_OUTPUT_DIR, replicate-N/ is created inside it.
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

export AF3_DATA_JSON=${AF3_DATA_JSON:-$AF3_OUTPUT_DIR/$AF3_NAME/${AF3_NAME}_data.json}

if [[ ! -f "$AF3_DATA_JSON" ]]; then
  echo "Missing $AF3_DATA_JSON. Run stage1.sh first." >&2
  exit 1
fi

# Node-local scratch and JAX cache. $LOCAL is deleted when the job ends.
export AF3_SCRATCH=${AF3_SCRATCH:-$LOCAL/af3}
export AF3_JAX_CACHE_DIR=${AF3_JAX_CACHE_DIR:-$AF3_SCRATCH/jax_cache}
mkdir -p "$AF3_SCRATCH/output" "$AF3_SCRATCH/tmp" "$AF3_JAX_CACHE_DIR"

# Copy results from $LOCAL to $AF3_OUTPUT_DIR when the script exits, even on failure.
trap 'rsync -a "$AF3_SCRATCH/output/" "$AF3_OUTPUT_DIR/"; print_elapsed' EXIT

export APPTAINERENV_TMPDIR="$AF3_SCRATCH/tmp"

run_alphafold \
  --json_path="$AF3_DATA_JSON" \
  --model_dir="$AF3_WEIGHTS" \
  --output_dir="$AF3_SCRATCH/output" \
  --jax_compilation_cache_dir="$AF3_JAX_CACHE_DIR" \
  --norun_data_pipeline
```

The script requests one L40S GPU (48 GB), which runs the default `triton`
attention with no extra settings. For very large complexes, change `--gpus` to
`h100-80:1`. Don't use the V100 GPUs (see [GPU notes](#gpu-notes-for-bridges-2)).

Both stages write to `$AF3_SCRATCH` on the node's local disk while they run and
copy the results to `$AF3_OUTPUT_DIR`. If a job hits its time limit, Slurm
allows only a short grace period before killing it, so set `--time` with some
margin.

#### Stage 2 running times

Elapsed time of each example's stage 2 job on `GPU-shared`, from the
`Elapsed time:` line at the end of its `af3-inference-<jobid>.out` log,
fastest to slowest. These cover inference only, not the data pipeline.

All of these jobs ran on a single NVIDIA L40S GPU (48 GB), requested with
`--gpus=l40s-48:1` as in `stage2.sh` above. Times on other GPU types, such as
the H100, will differ.

| Example | Job ID | GPU-shared (L40S) |
| --- | --- | --- |
| [`vanilla-examples/example9`](vanilla-examples/example9/) | 47414748 | 00:01:18 |
| [`vanilla-examples/example2`](vanilla-examples/example2/) | 47414741 | 00:01:19 |
| [`vanilla-examples/example3`](vanilla-examples/example3/) | 47414742 | 00:01:19 |
| [`vanilla-examples/example6`](vanilla-examples/example6/) | 47414745 | 00:01:19 |
| [`vanilla-examples/example7`](vanilla-examples/example7/) | 47414746 | 00:01:19 |
| [`vanilla-examples/example5`](vanilla-examples/example5/) | 47414744 | 00:01:20 |
| [`vanilla-examples/example8`](vanilla-examples/example8/) | 47414747 | 00:01:20 |
| [`vanilla-examples/example14`](vanilla-examples/example14/) | 47414753 | 00:01:20 |
| [`vanilla-examples/example13`](vanilla-examples/example13/) | 47414752 | 00:01:21 |
| [`vanilla-examples/example4`](vanilla-examples/example4/) | 47414743 | 00:01:43 |
| [`vanilla-examples/example11`](vanilla-examples/example11/) | 47414750 | 00:01:45 |
| [`vanilla-examples/example12`](vanilla-examples/example12/) | 47414751 | 00:01:47 |
| [`vanilla-examples/example10`](vanilla-examples/example10/) | 47414749 | 00:01:48 |
| [`vanilla-examples/example1`](vanilla-examples/example1/) | 47414740 | 00:02:52 |
| **Total** | | **00:21:50** |

### Resuming after a failure

AlphaFold 3 doesn't save checkpoints in the middle of a stage, but each stage's
output is kept:

- **Inference failed:** the `_data.json` from stage 1 is already in
  `output/replicate-N/<name>/`. Resubmit only stage 2 for that replicate,
  for example replicate 3:

  ```bash
  cd vanilla-examples/example1
  sbatch -A <allocation-id> --array=3 stage2.sh
  ```

- **Data pipeline failed:** submit both stages again, with `--array=N` for
  only the replicates that failed. Stage 1 starts over,
  because the data pipeline saves nothing until it finishes. If it ran out of
  time, increase `--time` in `stage1.sh`.

Submitting `stage1.sh` again after it has finished is also safe: each
replicate sees its existing `_data.json` and skips the data pipeline.

### Useful `run_alphafold.py` flags

| Flag | Description |
| --- | --- |
| `--json_path` / `--input_dir` | One input JSON, or a directory of them |
| `--output_dir` | Where results are written (required) |
| `--db_dir` | Database directory |
| `--model_dir` | Directory containing `af3.bin` or `af3.bin.zst` |
| `--run_data_pipeline` / `--norun_data_pipeline` | Turn the CPU MSA/template stage on or off |
| `--run_inference` / `--norun_inference` | Turn the GPU model stage on or off |
| `--jackhmmer_n_cpu`, `--nhmmer_n_cpu` | CPU threads for the MSA search tools |
| `--flash_attention_implementation` | `triton` (default, Ampere+), `cudnn` (Ampere+), or `xla` (slower fallback) |
| `--num_diffusion_samples` | Samples per seed (default 5) |
| `--num_seeds` | Generate this many seeds when the input has only one |
| `--jax_compilation_cache_dir` | Reuse compiled models between runs |
| `--max_template_date` | Exclude templates released after this date |
| `--save_embeddings`, `--save_distogram` | Write extra model outputs |

Run `run_alphafold --helpfull` after `module load alphafold3/3.0.4` to
list every flag.

## GPU notes for Bridges-2

| GPU | `--gpus=` | Notes |
| --- | --- | --- |
| NVIDIA L40S 48 GB | `l40s-48:1` | Used by the examples. Ada architecture; the default `triton` attention works. |
| NVIDIA H100 80 GB | `h100-80:1` | Best choice for large complexes; works with the default settings. |

Don't use the V100 GPUs (`v100-16`, `v100-32`). They are older than Ampere, so
they can't run the default attention, need XLA workarounds, and have less memory.

AlphaFold 3 uses a **single GPU** per prediction, so request exactly one:
`--gpus=<type>:1` on `GPU-shared`. That is also the minimum on `GPU-shared`.
More GPUs won't make one prediction faster; the extra GPUs sit idle and are
still charged to your allocation. Don't use the `GPU` partition for these jobs:
it allocates whole nodes (8 GPUs), so you'd pay for
7 idle GPUs. To process many inputs, submit one 1-GPU job per input or use a
Slurm job array.

Check the GPU types and partitions currently available with `sinfo` and the
[Bridges-2 User Guide](https://www.psc.edu/resources/bridges-2/user-guide/).

## Outputs

For each input, AlphaFold 3 writes a directory named after the job containing:

- `<name>_model.cif`: top-ranked predicted structure (mmCIF)
- `<name>_summary_confidences.json`: pTM, ipTM, ranking score, and other summary metrics
- `<name>_confidences.json`: per-atom pLDDT, PAE, and contact probabilities
- `<name>_data.json`: input augmented with MSAs and templates (reusable with `--norun_data_pipeline`)
- `<name>_ranking_scores.csv`: ranking score for every seed/sample
- `seed-<s>_sample-<n>/`: structure and confidences for each individual sample
- `TERMS_OF_USE.md`: output terms of use

See the upstream
[output documentation](https://github.com/google-deepmind/alphafold3/blob/main/docs/output.md)
for how to interpret the confidence metrics.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `RESOURCE_EXHAUSTED` / out of GPU memory | Enable [unified memory](#unified-memory-large-inputs-or-small-gpus), or use an H100 node |
| Triton/cuDNN attention errors | The job landed on an older GPU; check that `--gpus` is `l40s-48:1` or `h100-80:1` |
| Long time before inference starts | JAX compiles the model at the start of each job when the cache is on `$LOCAL`. Point `AF3_JAX_CACHE_DIR` at `$PROJECT` so later jobs reuse it |
| No `af3-inference` job after `af3-data` finished | The data pipeline failed, so Slurm cancelled stage 2. Check `af3-data-<jobid>.out`, fix the problem, and submit both stages again |
| `Failed to find the following module(s): "alphafold3"` | The module isn't on your `MODULEPATH`. Check `module avail alphafold3`, or add its directory with `module use <dir>` |
| `AlphaFold 3 container not found` when loading the module | The module's `.sif` file is missing from `$AF3_IMAGES`; load a version listed by `ls /ocean/containers/alphafold3` |
| `No such file or directory` for `/ocean/...` inside the container | `run_alphafold` binds `/ocean`, `$PROJECT` and `$LOCAL`. If you call `apptainer exec` yourself, add `--bind /ocean` (and `--bind $PROJECT`) ([bind paths docs](https://apptainer.org/docs/user/latest/bind_paths_and_mounts.html)) |
| Disk quota exceeded | Write outputs and caches to `$PROJECT`, not `$HOME` |

For Bridges-2 problems, contact PSC support at
[help@psc.edu](mailto:help@psc.edu). For AlphaFold 3 problems, check the
upstream [known issues](https://github.com/google-deepmind/alphafold3/blob/main/docs/known_issues.md)
and [issue tracker](https://github.com/google-deepmind/alphafold3/issues).

## Citing

If you publish results produced with AlphaFold 3, cite:

```bibtex
@article{Abramson2024,
  author  = {Abramson, Josh and Adler, Jonas and Dunger, Jack and others},
  journal = {Nature},
  title   = {Accurate structure prediction of biomolecular interactions with AlphaFold 3},
  year    = {2024},
  volume  = {630},
  number  = {8016},
  pages   = {493--500},
  doi     = {10.1038/s41586-024-07487-w}
}
```

Please also acknowledge your use of Bridges-2 and your ACCESS allocation as
described in the [PSC acknowledgement guidelines](https://www.psc.edu/resources/bridges-2/user-guide/).

## References

### AlphaFold 3 (Google DeepMind)

- Source code: <https://github.com/google-deepmind/alphafold3>
- Installation guide: <https://github.com/google-deepmind/alphafold3/blob/main/docs/installation.md>
- Input format: <https://github.com/google-deepmind/alphafold3/blob/main/docs/input.md>
- Output format: <https://github.com/google-deepmind/alphafold3/blob/main/docs/output.md>
- Performance and GPU configuration: <https://github.com/google-deepmind/alphafold3/blob/main/docs/performance.md>
- Known issues: <https://github.com/google-deepmind/alphafold3/blob/main/docs/known_issues.md>
- Model parameters download: <https://storage.googleapis.com/alphafold3/af3.bin.zst>
- Model Parameters Terms of Use: <https://github.com/google-deepmind/alphafold3/blob/main/WEIGHTS_TERMS_OF_USE.md>
- Model Parameters Prohibited Use Policy: <https://github.com/google-deepmind/alphafold3/blob/main/WEIGHTS_PROHIBITED_USE_POLICY.md>
- Output Terms of Use: <https://github.com/google-deepmind/alphafold3/blob/main/OUTPUT_TERMS_OF_USE.md>
- Issue tracker: <https://github.com/google-deepmind/alphafold3/issues>
- Contact: [alphafold@google.com](mailto:alphafold@google.com)
- AlphaFold Server (web interface, no install): <https://alphafoldserver.com>
- Paper: Abramson et al., *Nature* 630, 493–500 (2024). <https://doi.org/10.1038/s41586-024-07487-w>

### Container image

- Docker Hub image the Apptainer images are built from: <https://hub.docker.com/r/jurgjn/alphafold3>

### Apptainer

- Apptainer home page: <https://apptainer.org/>
- User guide: <https://apptainer.org/docs/user/latest/>
- Quick start: <https://apptainer.org/docs/user/latest/quick_start.html>
- GPU support (`--nv`): <https://apptainer.org/docs/user/latest/gpu.html>
- Bind paths and mounts (`--bind`): <https://apptainer.org/docs/user/latest/bind_paths_and_mounts.html>
- Environment variables (`--env`, `APPTAINERENV_`): <https://apptainer.org/docs/user/latest/environment_and_metadata.html>
- Using Docker/OCI images: <https://apptainer.org/docs/user/latest/docker_and_oci.html>
- `apptainer exec` reference: <https://apptainer.org/docs/user/latest/cli/apptainer_exec.html>
- `apptainer pull` reference: <https://apptainer.org/docs/user/latest/cli/apptainer_pull.html>
- Singularity compatibility: <https://apptainer.org/docs/user/latest/singularity_compatibility.html>
- Source code: <https://github.com/apptainer/apptainer>

### Bridges-2 and PSC

- Bridges-2 overview: <https://www.psc.edu/resources/bridges-2/>
- Bridges-2 User Guide (partitions, GPUs, file systems, Slurm): <https://www.psc.edu/resources/bridges-2/user-guide/>
- PSC support: [help@psc.edu](mailto:help@psc.edu)
- ACCESS allocations (request time on Bridges-2): <https://allocations.access-ci.org/>

### Databases

- UniProt / UniRef: <https://www.uniprot.org/>
- MGnify: <https://www.ebi.ac.uk/metagenomics/>
- BFD: <https://bfd.mmseqs.com/>
- PDB (RCSB): <https://www.rcsb.org/>
- Rfam: <https://rfam.org/>
- RNAcentral: <https://rnacentral.org/>
- NCBI Nucleotide: <https://www.ncbi.nlm.nih.gov/nucleotide/>

### Tools

- HMMER: <http://hmmer.org/>
- JAX: <https://github.com/jax-ml/jax>
- JAX persistent compilation cache: <https://docs.jax.dev/en/latest/persistent_compilation_cache.html>
- NVIDIA unified memory: <https://developer.nvidia.com/blog/unified-memory-cuda-beginners/>
