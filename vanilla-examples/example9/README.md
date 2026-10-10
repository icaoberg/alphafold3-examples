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
sbatch -A <allocation-id> stage1.sh
```

Stage 1 submits `stage2.sh` itself when it starts, with a dependency on the
stage 1 job. Each stage is a Slurm job array of 5 tasks, one per replicate, so
you can average the running times. Stage 2 task N waits until stage 1 task N
succeeds, and Slurm cancels it if that task fails. Each replicate runs the full
data pipeline. Add `--array=1` to the `sbatch` command for a single run.

Watch the jobs with `squeue -u $USER`. Replicate N writes its results to
`output/replicate-N/streptavidin_biotin_smiles/` and its logs to `af3-data-<jobid>_N.out` and
`af3-inference-<jobid>_N.out`. The predicted structure is
`streptavidin_biotin_smiles_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
