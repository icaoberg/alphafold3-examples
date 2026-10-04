# Example 6: Methylated double-stranded DNA

Predicts a 20-bp double-stranded DNA (chains `A` and `B`) with 5-methylcytosine
(CCD `5CM`) at every CpG site on both strands, given as `modifications` on each
DNA chain. DNA chains have no MSA, so stage 1 is quick. The input is
`examples/methylated_dna.json` from the upstream AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: Two DNA strands (`A`, `B`) with 5-methylcytosine modifications |
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
`$PROJECT/af3_output/methylated_CpG_dsDNA/`. The predicted structure is
`methylated_CpG_dsDNA_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
