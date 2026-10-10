# Example 4: Phosphorylated protein (ERK2 pThr185/pTyr187)

Predicts human ERK2/MAPK1 (chain `A`, 360 residues, UniProt
[P28482](https://www.uniprot.org/uniprotkb/P28482)) with its activation loop
dually phosphorylated: phosphothreonine at 185 (CCD `TPO`) and phosphotyrosine
at 187 (CCD `PTR`), given as `modifications` on the protein. The input is
`examples/erk2_phosphorylated.json` from the upstream AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: One protein sequence (`A`) with two post-translational modifications |
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
`output/replicate-N/ERK2_dual_phosphorylated/` and its logs to `af3-data-<jobid>_N.out` and
`af3-inference-<jobid>_N.out`. The predicted structure is
`ERK2_dual_phosphorylated_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
