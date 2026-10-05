# Example 9: Protein + ligand from SMILES (streptavidin–biotin)

Predicts core streptavidin from *Streptomyces avidinii* (chain `A`, 126
residues, UniProt [P22629](https://www.uniprot.org/uniprotkb/P22629)) bound to
D-biotin (chain `B`). The ligand is given as a SMILES string instead of a CCD
code. The input is `examples/streptavidin_biotin_smiles.json` from the upstream
AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: One protein sequence (`A`) and one SMILES ligand (`B`) |
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
`$PROJECT/af3_output/streptavidin_biotin_smiles/`. The predicted structure is
`streptavidin_biotin_smiles_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
