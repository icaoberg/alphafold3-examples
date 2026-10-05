# Example 8: Glycoprotein (RNase B + N-glycan)

Predicts bovine ribonuclease B (chain `A`, 124 residues, UniProt
[P61823](https://www.uniprot.org/uniprotkb/P61823)) with a core N-linked glycan
(Man3GlcNAc2, chain `B`) attached to Asn34. The glycan is a multi-residue ligand
(`NAG`, `NAG`, `BMA`, `MAN`, `MAN`) whose glycosidic bonds and attachment to the
protein are given in `bondedAtomPairs`. The input is
`examples/rnaseb_glycosylated.json` from the upstream AlphaFold 3 repository.

## Files

| File | What it does |
| --- | --- |
| `fold_input.json` | Input: One protein (`A`), one glycan ligand (`B`), and bonds in `bondedAtomPairs` |
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
`$PROJECT/af3_output/RNaseB_glycosylated/`. The predicted structure is
`RNaseB_glycosylated_model.cif`.

See the [main README](../README.md) for how the scripts work, how to change
paths and GPU types, and how to resume after a failure.
