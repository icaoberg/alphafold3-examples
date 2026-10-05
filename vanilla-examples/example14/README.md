# Example 14: Protein monomer (ubiquitin)

Predicts human ubiquitin (chain `A`, 76 residues, UniProt
[P0CG48](https://www.uniprot.org/uniprotkb/P0CG48)), a single small protein. It
is the fastest example to run. The input is `examples/ubiquitin_monomer.json`
from the upstream AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: One protein sequence (`A`) |
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
`$PROJECT/af3_output/ubiquitin_monomer/`. The predicted structure is
`ubiquitin_monomer_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
