# Example 2: protein heterodimer (barnase–barstar)

Predicts the structure of a heterodimer of two different proteins from
*Bacillus amyloliquefaciens*: the ribonuclease barnase (chain `A`, 110 residues,
UniProt [P00648](https://www.uniprot.org/uniprotkb/P00648)) bound to its
inhibitor barstar (chain `B`, 89 residues, UniProt
[P11540](https://www.uniprot.org/uniprotkb/P11540)). The input is
`examples/barnase_barstar.json` from the upstream AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: two protein sequences, barnase (`A`) and barstar (`B`) |
| `stage1.sh` | Stage 1 on `RM-shared` (CPU only): builds MSAs and finds templates |
| `stage2.sh` | Stage 2 on `GPU-shared` (one GPU): predicts the structure |

## Run it

From this directory:

```bash
sbatch -A <allocation-id> stage1.sh
```

Stage 1 submits `stage2.sh` itself when it starts, with a dependency on the
stage 1 job. Each stage is a Slurm job array of 5 tasks, one per replicate, so
you can average the running times. Stage 2 task N waits until stage 1 task N
succeeds, and Slurm cancels it if that task fails. Each replicate runs the full
data pipeline. Add `--array=1` to the `sbatch` command for a single run.

Watch the jobs with `squeue -u $USER`. Replicate N writes its results to
`output/replicate-N/barnase_barstar_complex/` and its logs to `af3-data-<jobid>_N.out` and
`af3-inference-<jobid>_N.out`. The predicted structure is
`barnase_barstar_complex_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
