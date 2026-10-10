# Example 5: Covalent ligand (KRAS G12C + sotorasib)

Predicts human KRAS4B with the G12C mutation (chain `A`, 189 residues, UniProt
[P01116](https://www.uniprot.org/uniprotkb/P01116)) covalently bound to the
inhibitor sotorasib (chain `B`, CCD `MOV`). The covalent bond between Cys12 `SG`
and the ligand is given in `bondedAtomPairs`. The input is
`examples/kras_g12c_sotorasib.json` from the upstream AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: One protein (`A`), one CCD ligand (`B`), and a covalent bond in `bondedAtomPairs` |
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
`output/replicate-N/KRAS_G12C_sotorasib_covalent/` and its logs to `af3-data-<jobid>_N.out` and
`af3-inference-<jobid>_N.out`. The predicted structure is
`KRAS_G12C_sotorasib_covalent_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
