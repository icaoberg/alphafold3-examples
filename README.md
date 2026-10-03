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

2. Go to an example directory and submit its two jobs (data pipeline on
   `RM-shared`, then inference on `GPU-shared`):

   ```bash
   cd example1
   ./submit_af3.sh <allocation-id>
   ```

3. Watch the jobs with `squeue -u $USER`. Results are written to
   `$PROJECT/af3_output/<name>/`.

## Environment variables

The job scripts read these environment variables and fall back to the defaults
below. `submit_af3.sh` submits with `--export=ALL`, so any of them you export
before running it are passed to both jobs.

### Paths used by the examples

| Variable | Default on Bridges-2 | Purpose |
| --- | --- | --- |
| `AF3_ROOT` | `/ocean/datasets/community/alphafold3` | Root of the shared install |
| `AF3_IMAGE` | `/ocean/containers/alphafold3/singularity-alphafold3-v3.0.4.sif` | Apptainer image to run |
| `AF3_DB_DIR` | `$AF3_ROOT/databases` | Passed to `--db_dir` |
| `AF3_MODEL_DIR` | `$AF3_ROOT/weights` | Passed to `--model_dir` |
| `AF3_INPUT` | *(set by `submit_af3.sh`)* | Input JSON file passed to `--json_path` in stage 1 |
| `AF3_NAME` | *(set by `submit_af3.sh`)* | The input's `name`; used to find `<name>/<name>_data.json` |
| `AF3_OUTPUT_DIR` | `$PROJECT/af3_output` | Passed to `--output_dir` |
| `AF3_JAX_CACHE_DIR` | `$LOCAL/af3/jax_cache` | Passed to `--jax_compilation_cache_dir` |
| `AF3_SCRATCH` | `$LOCAL/af3` | Node-local scratch for temporary files and in-progress output (batch jobs only) |

For example, to use an older image and a different output directory:

```bash
export AF3_IMAGE=/ocean/containers/alphafold3/singularity-alphafold3-v3.0.3.sif
export AF3_OUTPUT_DIR=$PROJECT/af3_output_v3.0.3
cd example1
./submit_af3.sh <allocation-id>
```

Write output to `$PROJECT`, not `$HOME`. Your home directory quota is small.

`$LOCAL` is fast disk on the compute node your job runs on. It exists only
while the job runs and is deleted when the job ends, so the job scripts use it
for scratch and the JAX compilation cache, and copies the results to
`$PROJECT` before the job exits. Because the cache is deleted with the job, each
new job compiles the model again (usually a few minutes). To reuse compiled
models across jobs, set `AF3_JAX_CACHE_DIR=$PROJECT/.cache/af3_jax` instead.

### Variables read by JAX/XLA inside the container

These control GPU memory and compilation. The upstream container image sets
defaults for some of them.

| Variable | Upstream default | When to change it |
| --- | --- | --- |
| `XLA_FLAGS` | `--xla_gpu_enable_triton_gemm=false` | On **V100** GPUs, set `--xla_disable_hlo_passes=custom-kernel-fusion-rewriter` to avoid known numerical errors |
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
>   --env XLA_FLAGS="--xla_disable_hlo_passes=custom-kernel-fusion-rewriter" \
>   ...
> # or
> export APPTAINERENV_XLA_FLAGS="--xla_disable_hlo_passes=custom-kernel-fusion-rewriter"
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
protein homodimer example (`example1/fold_input.json`):

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
only while the model runs:

Each example has its own directory with everything it needs to run:

| Example | Directory | What it predicts |
| --- | --- | --- |
| 1 | [`example1/`](example1/) | Protein homodimer (PDB 2PV7) |

Each example directory contains the same four files:

| File | What it does |
| --- | --- |
| `fold_input.json` | The input |
| `af3_data_pipeline.sbatch` | Stage 1 on `RM-shared` (32 cores, about 60 GB of memory) with `--norun_inference` |
| `af3_inference.sbatch` | Stage 2 on `GPU-shared` (1 GPU) with `--norun_data_pipeline` |
| `submit_af3.sh` | Submits both jobs, with inference set to start only if stage 1 succeeds |

The scripts are the same in every example; only `fold_input.json` changes. To
fold your own input, copy an example directory and replace `fold_input.json`.

### Submit both stages

From an example directory:

```bash
./submit_af3.sh <allocation-id>
```

To use a different input file, pass it as a second argument:
`./submit_af3.sh <allocation-id> my_input.json`.

`submit_af3.sh` reads the `name` from the input JSON and passes it to both jobs
as `AF3_NAME`, along with `AF3_INPUT`. The inference job runs with
`--dependency=afterok`, so it starts only after the data pipeline finishes
without errors. If the data pipeline fails, the inference job stays pending
with reason `DependencyNeverSatisfied`; cancel it with `scancel`.

### Stage 1: data pipeline on RM-shared

`example1/af3_data_pipeline.sbatch`:

```bash
#!/bin/bash
#SBATCH --job-name=af3-data
#SBATCH --partition=RM-shared
#SBATCH --ntasks-per-node=32
#SBATCH --time=12:00:00
#SBATCH --output=%x-%j.out

# Stage 1: build MSAs and find templates (CPU only).
# Submit with submit_af3.sh, which sets AF3_INPUT and AF3_NAME.

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
```

This writes `<name>/<name>_data.json` to `$AF3_OUTPUT_DIR`. That file holds the
MSAs and templates. `RM-shared` gives each core about 1.9 GB of memory, so the
32 cores also give the MSA search tools about 60 GB.

### Stage 2: inference on GPU-shared

`example1/af3_inference.sbatch`:

```bash
#!/bin/bash
#SBATCH --job-name=af3-inference
#SBATCH --partition=GPU-shared
#SBATCH --gpus=v100-32:1
#SBATCH --ntasks-per-node=5
#SBATCH --time=02:00:00
#SBATCH --output=%x-%j.out

# Stage 2: predict the structure from the stage 1 output (one GPU).
# Submit with submit_af3.sh, which sets AF3_NAME.

set -euo pipefail

: "${AF3_NAME:?Set AF3_NAME to the job name from the input JSON}"

export AF3_ROOT=/ocean/datasets/community/alphafold3
export AF3_IMAGE=${AF3_IMAGE:-/ocean/containers/alphafold3/singularity-alphafold3-v3.0.4.sif}
export AF3_MODEL_DIR=${AF3_MODEL_DIR:-$AF3_ROOT/weights}
export AF3_OUTPUT_DIR=${AF3_OUTPUT_DIR:-$PROJECT/af3_output}
export AF3_DATA_JSON=${AF3_DATA_JSON:-$AF3_OUTPUT_DIR/$AF3_NAME/${AF3_NAME}_data.json}

if [[ ! -f "$AF3_DATA_JSON" ]]; then
  echo "Missing $AF3_DATA_JSON. Run af3_data_pipeline.sbatch first." >&2
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
```

The script checks which GPU it got and sets the V100 workarounds only when it
needs them, so you can change `--gpus` to `l40s-48:1` or `h100-80:1` without
editing anything else.

Both stages write to `$AF3_SCRATCH` on the node's local disk while they run,
and the `trap` copies the results to `$AF3_OUTPUT_DIR` when the script exits.
If a job hits its time limit, Slurm allows only a short grace period before
killing it, so set `--time` with some margin.

### Resuming after a failure

AlphaFold 3 doesn't save checkpoints in the middle of a stage, but each stage's
output is kept:

- **Inference failed:** the `_data.json` from stage 1 is already in
  `$AF3_OUTPUT_DIR/<name>/`. Resubmit only stage 2:

  ```bash
  cd example1
  sbatch -A <allocation-id> --export=ALL,AF3_NAME=2PV7 af3_inference.sbatch
  ```

- **Data pipeline failed:** run `submit_af3.sh` again. Stage 1 starts over,
  because the data pipeline saves nothing until it finishes. If it ran out of
  time, increase `--time` in `af3_data_pipeline.sbatch`.

Running `submit_af3.sh` again after stage 1 has finished is also safe: the
data pipeline job sees the existing `_data.json`, exits right away, and the
inference job starts.

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
| `--flash_attention_implementation` | `triton` (default, Ampere+), `cudnn` (Ampere+), or `xla` (any GPU; **required on V100**) |
| `--num_diffusion_samples` | Samples per seed (default 5) |
| `--num_seeds` | Generate this many seeds when the input has only one |
| `--jax_compilation_cache_dir` | Reuse compiled models between runs |
| `--max_template_date` | Exclude templates released after this date |
| `--save_embeddings`, `--save_distogram` | Write extra model outputs |

Run `python /app/alphafold/run_alphafold.py --helpfull` inside the container to
list every flag.

## GPU notes for Bridges-2

| GPU | `--gpus=` | Notes |
| --- | --- | --- |
| NVIDIA V100 16/32 GB | `v100-16:1`, `v100-32:1` | Compute capability 7.0. Needs `XLA_FLAGS=--xla_disable_hlo_passes=custom-kernel-fusion-rewriter` and `--flash_attention_implementation=xla`; `af3_inference.sbatch` sets both when it detects a V100. With unified memory, inputs up to about 1,280 tokens fit. |
| NVIDIA L40S 48 GB | `l40s-48:1` | Ada architecture; the default `triton` attention works. |
| NVIDIA H100 80 GB | `h100-80:1` | Best choice for large complexes; works with the default settings. |

AlphaFold 3 uses a **single GPU** per prediction, so request exactly one:
`--gpus=<type>:1` on `GPU-shared`. That is also the minimum on `GPU-shared`.
More GPUs won't make one prediction faster; the extra GPUs sit idle and are
still charged to your allocation. Don't use the `GPU` partition for these jobs:
it allocates whole nodes (8 GPUs, or 16 on one V100 node), so you'd pay for
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
| Wrong or `NaN` structures on V100 | Set `XLA_FLAGS` with `--env` or `APPTAINERENV_` (see the [warning above](#variables-read-by-jaxxla-inside-the-container)) and use `--flash_attention_implementation=xla` |
| `RESOURCE_EXHAUSTED` / out of GPU memory | Enable [unified memory](#unified-memory-large-inputs-or-small-gpus), or use an H100 node |
| Triton/cuDNN attention errors | The GPU is older than Ampere; use `--flash_attention_implementation=xla` |
| Long time before inference starts | JAX compiles the model at the start of each job when the cache is on `$LOCAL`. Point `AF3_JAX_CACHE_DIR` at `$PROJECT` so later jobs reuse it |
| Inference job stuck in `PD` with `DependencyNeverSatisfied` | The data pipeline job failed. Check its `af3-data-<jobid>.out`, cancel the inference job, fix the problem, and run `submit_af3.sh` again |
| `No such file or directory` for `/ocean/...` inside the container | Add `--bind /ocean` (and `--bind $PROJECT`) to `apptainer exec` ([bind paths docs](https://apptainer.org/docs/user/latest/bind_paths_and_mounts.html)) |
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
