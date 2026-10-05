# Example 13: Protein–RNA complex (U1A + RNA hairpin)

Predicts the RRM1 domain of human U1A (chain `A`, 101 residues, UniProt
[P09012](https://www.uniprot.org/uniprotkb/P09012)) bound to the 21-nt U1 snRNA
stem-loop II hairpin (chain `B`), as in PDB
[1URN](https://www.rcsb.org/structure/1URN). The input is
`examples/u1a_rna_hairpin.json` from the upstream AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: One protein sequence (`A`) and one RNA sequence (`B`) |
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
`$PROJECT/af3_output/U1A_RNA_hairpin/`. The predicted structure is
`U1A_RNA_hairpin_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
