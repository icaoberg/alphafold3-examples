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
sbatch -A <allocation-id> stage1.sh
```

Stage 1 submits `stage2.sh` itself when it starts, with a dependency on the
stage 1 job. Each stage is a Slurm job array of 5 tasks, one per replicate, so
you can average the running times. Stage 2 task N waits until stage 1 task N
succeeds, and Slurm cancels it if that task fails. Each replicate runs the full
data pipeline. Add `--array=1` to the `sbatch` command for a single run.

Watch the jobs with `squeue -u $USER`. Replicate N writes its results to
`output/replicate-N/TetR_homodimer/` and its logs to `af3-data-<jobid>_N.out` and
`af3-inference-<jobid>_N.out`. The predicted structure is
`TetR_homodimer_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
