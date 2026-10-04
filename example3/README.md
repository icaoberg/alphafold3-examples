# Example 3: Protein with ions (calmodulin + 4 Ca²⁺)

Predicts human calmodulin-1 (chain `A`, 149 residues, UniProt
[P0DP23](https://www.uniprot.org/uniprotkb/P0DP23)) with four calcium ions
(chains `B`–`E`, CCD `CA`), one for each EF-hand binding site. The input is
`examples/calmodulin_4calcium.json` from the upstream AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: One protein sequence (`A`) and four calcium ions (`B`–`E`) |
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
`$PROJECT/af3_output/calmodulin_4calcium/`. The predicted structure is
`calmodulin_4calcium_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
