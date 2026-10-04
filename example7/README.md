# Example 7: Modified RNA (tRNA-like fragment)

Predicts a 25-nt tRNA-like RNA fragment (chain `A`) with three modified
nucleotides: 2'-O-methylguanosine (CCD `OMG`) at 4, pseudouridine (CCD `PSU`) at
13, and 5-methylcytidine (CCD `5MC`) at 18. The input is
`examples/modified_rna.json` from the upstream AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: One RNA sequence (`A`) with three modified nucleotides |
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
`$PROJECT/af3_output/modified_RNA_hairpin/`. The predicted structure is
`modified_RNA_hairpin_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
