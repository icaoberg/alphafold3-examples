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
jobid=$(sbatch --parsable -A <allocation-id> stage1.sh)
sbatch -A <allocation-id> --dependency=afterok:$jobid --kill-on-invalid-dep=yes stage2.sh
```

Stage 2 waits until stage 1 succeeds, and Slurm cancels it if stage 1 fails.

Watch the jobs with `squeue -u $USER`. Results are written to
`$PROJECT/af3_output/KRAS_G12C_sotorasib_covalent/`. The predicted structure is
`KRAS_G12C_sotorasib_covalent_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
