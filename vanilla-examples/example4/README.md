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
jobid=$(sbatch --parsable -A <allocation-id> stage1.sh)
sbatch -A <allocation-id> --dependency=afterok:$jobid --kill-on-invalid-dep=yes stage2.sh
```

Stage 2 waits until stage 1 succeeds, and Slurm cancels it if stage 1 fails.

Watch the jobs with `squeue -u $USER`. Results are written to
`$PROJECT/af3_output/ERK2_dual_phosphorylated/`. The predicted structure is
`ERK2_dual_phosphorylated_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
