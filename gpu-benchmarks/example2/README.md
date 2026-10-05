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
jobid=$(sbatch --parsable -A <allocation-id> stage1.sh)
sbatch -A <allocation-id> --dependency=afterok:$jobid --kill-on-invalid-dep=yes stage2.sh
```

Stage 2 waits until stage 1 succeeds, and Slurm cancels it if stage 1 fails.

Watch the jobs with `squeue -u $USER`. Results are written to
`$PROJECT/af3_output/barnase_barstar_complex/`. The predicted structure is
`barnase_barstar_complex_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
