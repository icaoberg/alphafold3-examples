# Token-size sweep benchmark

Times AlphaFold 3 inference (stage 2 only) on synthetic inputs covering every
default compilation bucket from 256 to 5,120 tokens on Bridges-2
`GPU-shared`, on V100 (`v100-32`), L40S (`l40s-48`, in the `alphafold3`
reservation) and H100 (`h100-80`), five rounds each. The goal is
to see how runtime and GPU memory scale with input size, and the largest input
each GPU can run.

This complements `../gpu-benchmarks/`, which times the 14 real examples on the
same GPUs. Those examples have fixed sizes, and every run includes JAX
compilation. This sweep varies the size and separates compilation from
compute.

## Inputs

`gen_token_inputs.py` writes `inputs/tokens<N>.json` for N = 256, 512, 768,
1024, 1280, 1536, 2048, 2560, 3072, 3584, 4096, 4608 and 5120 (the default
buckets in `run_alphafold.py`, so no input is padded):

- A single protein chain of N random amino acids. Standard amino acids are one
  token each, so the input has exactly N tokens.
- Each size uses its own fixed random seed, so the inputs are identical every
  time they are generated. `inputs/` is not tracked by git.
- Empty MSA and templates, so the input runs with `--norun_data_pipeline` and
  needs no stage 1. Runtime depends on the token count, not the sequence, so
  the predicted structures are meaningless but the timings are valid.
- Two model seeds. Seed 1 includes JAX compilation (**cold**); seed 2 reuses
  the compiled model (**warm**). The warm time is the one to compare with
  DeepMind's compile-free timings in AlphaFold 3's `docs/performance.md`.

Other sizes can be passed as arguments, e.g. `./gen_token_inputs.py 6144`.
Sizes above 5,120 need their own compilation bucket and will most likely run
out of memory without unified memory.

## Run it

From this directory:

```bash
chmod +x *.sh *.py
export AF3_MODEL_DIR=<directory containing af3.bin>

./submit_sweep.sh -A <allocation-id> -r 1 -R 5 -n   # dry run: print sbatch only
./submit_sweep.sh -A <allocation-id> -r 1 -R 5      # 5 rounds x 13 sizes x 3 GPUs
```

- All five rounds are queued at once, but never overlap: each round depends
  (`--dependency=afterany`) on every job of the round before it, including
  jobs of that round already in the queue, so runs don't share nodes with
  each other. `-r 3 -R 5` queues only rounds 3 to 5, and `-r 2` alone queues
  one round.
- Runs that already succeeded, are queued, or ran out of memory are skipped,
  so resubmitting a round only retries runs that failed for other reasons.
- Missing inputs are generated with `gen_token_inputs.py`, so it doesn't need
  to be run first.
- Pass sizes to run only those (`./submit_sweep.sh -A <id> -r 1 256 512`).
- Set `GPUS` to change the GPU types (`GPUS="l40s-48" ./submit_sweep.sh ...`).
- The `RESERVATION` (default `alphafold3`) is used only for the GPU types in
  `RESERVATION_GPUS` (default `l40s-48`); the others are submitted without it.
  Set `RESERVATION=` to never use one.
- Wall-time limits scale with size, from 30 minutes up to 4 hours, doubled on
  V100.

Then collect and plot:

```bash
./collect_sweep.py
./plot_sweep.py
```

Commit `sweep_results.csv`, `sweep_summary.csv` and `plots/` to keep the
numbers. Logs and `output/` are not tracked by git.

## What gets recorded

Each job writes `logs/af3-sweep-tokens<N>-<gpu>-r<repeat>[-mem]-<jobid>.out`,
and its outputs go to `output/tokens<N>/<gpu>/r<repeat>[-mem]/`.

`sweep_results.csv` has one row per run:

| Column | Source |
| --- | --- |
| `cold_seconds` | Seed 1 `Running model inference ... took` line: compilation plus compute |
| `warm_seconds` | Seed 2: compute only, comparable to DeepMind's table |
| `compile_seconds` | `cold_seconds - warm_seconds` |
| `featurisation_seconds` | `Featurising data ... took` (CPU work, not the GPU) |
| `peak_gpu_mem_mib` | JAX `peak_bytes_in_use`: real peak memory inside XLA's pool |
| `smi_peak_mib` | Highest `nvidia-smi` reading (only the 95% preallocation unless `-m`) |
| `status` | `ok`, `oom`, `timeout`, `failed`, or `incomplete` |
| `attention` | `triton`, or `xla` on V100 |

`sweep_summary.csv` has one row per GPU and size: median timings over the
successful runs (timings from timing runs, memory from any run), and
DeepMind's A100/H100 timings where a size matches their table.

`plot_sweep.py` writes:

- `plots/sweep_runtime.png`: warm time vs tokens per GPU, with DeepMind's
  A100/H100 timings and OOM points
- `plots/sweep_compile.png`: cold vs warm time (compilation overhead)
- `plots/sweep_memory.png`: real peak memory vs tokens, against each card's
  capacity

## GPU memory

XLA preallocates 95% of GPU memory when the job starts, so `nvidia-smi` shows
roughly the whole card whatever the input size. That number is kept as
`smi_peak_mib` but says nothing about the input.

Instead, `sweep.sh` runs `run_alphafold.py` through a small wrapper that, when
the run ends (even after an error), prints JAX's own `peak_bytes_in_use` for
the GPU: the most memory actually used inside the preallocated pool. This is
`peak_gpu_mem_mib`, recorded in every run without changing the timings.
`jax_limit_mib` is the size of the pool.

`-m` additionally turns off preallocation (`XLA_PYTHON_CLIENT_PREALLOCATE=false`)
as a cross-check against `nvidia-smi`. It isn't needed for normal runs.

## V100 runs

As in `../gpu-benchmarks/`, `sweep.sh` uses XLA attention and adds
`--xla_disable_hlo_passes=custom-kernel-fusion-rewriter` to `XLA_FLAGS` when
`nvidia-smi` reports a V100. DeepMind reports a limit of about 1,280 tokens
on V100 with unified memory, which is not enabled here, so larger sizes are
expected to be `oom`.

## Limitations

- No MSA. Real inputs with deep MSAs do extra work in the MSA module, so these
  timings slightly underestimate real proteins of the same size.
- Single protein chain only. Ligands, nucleic acids and multiple chains are
  not covered.
- Unified memory is not enabled, so inputs too large for a GPU are recorded as
  `oom` rather than run more slowly.
