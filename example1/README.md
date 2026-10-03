# Example 1: protein homodimer (PDB 2PV7)

Predicts the structure of a homodimer: two copies (chains `A` and `B`) of the
same 298-residue protein from PDB entry
[2PV7](https://www.rcsb.org/structure/2PV7). This is the example input from the
upstream AlphaFold 3 documentation.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: one protein sequence, used for chains `A` and `B` |
| `submit_af3.sh` | Stage 1 on `RM-shared` (CPU only): builds MSAs and finds templates, then submits stage 2 |
| `af3_inference.sbatch` | Stage 2 on `GPU-shared` (one GPU): predicts the structure |

## Run it

From this directory:

```bash
sbatch -A <allocation-id> submit_af3.sh
```

Watch the jobs with `squeue -u $USER`. Results are written to
`$PROJECT/af3_output/2PV7/`. The predicted structure is `2PV7_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
