# Stage 2 GPU benchmarks

Times stage 2 (inference) of the 14 examples on each GPU type on Bridges-2
`GPU-shared`: V100 (`v100-32`), L40S (`l40s-48`) and H100 (`h100-80`).

Stage 1 has already run for every example, so only stage 2 is submitted. The
`stage2.sh` script is the same in every example directory.

## Run it

Submit one round (14 examples × 3 GPUs = 42 jobs), and wait until it finishes
before submitting the next, so runs don't share nodes with each other:

```bash
./submit_all.sh -A <allocation-id> -r 1
# when round 1 is done (squeue -u $USER is empty):
./submit_all.sh -A <allocation-id> -r 2
# ... up to -r 5
```

Add `-n` to print the `sbatch` commands without submitting. Pass example
directories to run only those (`./submit_all.sh -A <id> -r 1 example1`), and
set `GPUS` to change the GPU types (`GPUS="l40s-48 h100-80" ./submit_all.sh ...`).

Runs that already succeeded or are still queued are skipped, so running the
same round again resubmits only the ones that failed.

Then collect the timings:

```bash
./collect_results.py
```

This writes `results.csv` with one row per run and prints the median inference
time per example and GPU. The `.out` logs and `output/` are not tracked by git,
so commit `results.csv` to keep the numbers.

## What gets recorded

Each job writes `example<N>/af3-s2-example<N>-<gpu>-r<repeat>-<jobid>.out`,
and its predicted structures go to `example<N>/output/stage2/<gpu>/r<repeat>/`.

| Column | Source |
| --- | --- |
| `inference_seconds` | AlphaFold 3's `Running model inference with seed ... took` line. Includes JAX compilation, which happens on every run because the cache is on node-local `$LOCAL`. Use this column to compare GPUs. |
| `featurisation_seconds` | `Featurising data ... took` (CPU work, not the GPU) |
| `elapsed_seconds` | The whole job: container start, featurisation, inference and copying results |
| `status` | `ok`, `oom`, `timeout`, `failed`, or `incomplete` (still running or killed) |
| `attention` | `triton`, or `xla` on V100 (see below) |
| `gpu_name`, `gpu_memory`, `node` | From `nvidia-smi` and `hostname` on the node that ran the job |

## V100 runs

AlphaFold 3 refuses to run on V100s (compute capability 7.0) unless two
workarounds are set, and `stage2.sh` sets them when `nvidia-smi` reports a
V100:

- `--flash_attention_implementation=xla`, because the Triton and cuDNN
  attention kernels need Ampere or newer GPUs
- `--xla_disable_hlo_passes=custom-kernel-fusion-rewriter` in `XLA_FLAGS`, for
  a known numerical issue on these GPUs

The V100 times therefore measure the slower XLA attention, which is the only
way AlphaFold 3 runs on these GPUs. Unified memory isn't enabled, so an input
too large for 32 GB is recorded as `oom` rather than run more slowly.
