# Example 12: Protein homodimer (TetR)

Predicts a homodimer of the *E. coli* tetracycline repressor TetR class D
(chains `A` and `B`, 218 residues, UniProt
[P0ACT4](https://www.uniprot.org/uniprotkb/P0ACT4)) with no DNA or ligand.
Compare it with examples 10 and 11. The input is `examples/tetr_homodimer.json`
from the upstream AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: One protein sequence, used for chains `A` and `B` |
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
`$PROJECT/af3_output/TetR_homodimer/`. The predicted structure is
`TetR_homodimer_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
