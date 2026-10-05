# Vanilla examples: results

Results from running all 14 vanilla examples on Bridges-2 with AlphaFold 3
v3.0.4 (`singularity-alphafold3-v3.0.4.sif`). Each example ran as two Slurm
jobs, using the `stage1.sh` and `stage2.sh` scripts in its directory:

| Stage | Partition | Resources | Ran |
| --- | --- | --- | --- |
| 1: data pipeline | `RM-shared` | 32 cores (about 64 GB of memory) | 2026-10-04 |
| 2: inference | `GPU-shared` | 1 NVIDIA L40S (48 GB), `--gpus=l40s-48:1` | 2026-10-05 |

These runs used the job scripts from before they loaded the `alphafold3`
module. The scripts now load the module, which runs the same container,
databases and weights. Every job finished and wrote a predicted structure.

The job logs (`af3-data-<jobid>.out`, `af3-inference-<jobid>.out`) and the
`output/` directories are kept in each example directory but are ignored by
Git, so this file records the results.

## Running times

Elapsed times come from the `Elapsed time:` line at the end of each job log.
Tokens is the input size AlphaFold 3 reports in the stage 2 log.

| Example | What it predicts | Tokens | Stage 1 job | Stage 1 (RM-shared) | Stage 2 job | Stage 2 (L40S) | Total |
| --- | --- | ---: | --- | ---: | --- | ---: | ---: |
| [`example1`](example1/) | Protein homodimer (PDB 2PV7) | 596 | 47398729 | 00:14:46 | 47414740 | 00:02:52 | 00:17:38 |
| [`example2`](example2/) | Protein heterodimer (barnase–barstar) | 199 | 47398731 | 01:57:39 | 47414741 | 00:01:19 | 01:58:58 |
| [`example3`](example3/) | Protein with ions (calmodulin + 4 Ca²⁺) | 153 | 47398840 | 00:15:16 | 47414742 | 00:01:19 | 00:16:35 |
| [`example4`](example4/) | Phosphorylated protein (ERK2 pThr185/pTyr187) | 385 | 47398841 | 00:33:29 | 47414743 | 00:01:43 | 00:35:12 |
| [`example5`](example5/) | Covalent ligand (KRAS G12C + sotorasib) | 230 | 47398842 | 00:16:10 | 47414744 | 00:01:20 | 00:17:30 |
| [`example6`](example6/) | Methylated double-stranded DNA | 192 | 47398843 | 00:00:15 | 47414745 | 00:01:19 | 00:01:34 |
| [`example7`](example7/) | Modified RNA (tRNA-like fragment) | 87 | 47398844 | 01:13:41 | 47414746 | 00:01:19 | 01:15:00 |
| [`example8`](example8/) | Glycoprotein (RNase B + N-glycan) | 185 | 47398845 | 01:31:54 | 47414747 | 00:01:20 | 01:33:14 |
| [`example9`](example9/) | Protein + ligand from SMILES (streptavidin–biotin) | 142 | 47398847 | 01:04:18 | 47414748 | 00:01:18 | 01:05:36 |
| [`example10`](example10/) | Protein–DNA complex (TetR dimer + tetO) | 476 | 47398848 | 00:13:53 | 47414749 | 00:01:48 | 00:15:41 |
| [`example11`](example11/) | Protein homodimer + ligands (TetR + tetracycline) | 500 | 47398849 | 00:13:53 | 47414750 | 00:01:45 | 00:15:38 |
| [`example12`](example12/) | Protein homodimer (TetR) | 436 | 47398863 | 00:13:17 | 47414751 | 00:01:47 | 00:15:04 |
| [`example13`](example13/) | Protein–RNA complex (U1A + RNA hairpin) | 122 | 47398864 | 01:28:26 | 47414752 | 00:01:21 | 01:29:47 |
| [`example14`](example14/) | Protein monomer (ubiquitin) | 76 | 47398865 | 00:16:59 | 47414753 | 00:01:20 | 00:18:19 |
| **Total** | | | | **09:33:56** | | **00:21:50** | **09:55:46** |

Stage 1 (the CPU-only MSA and template search) takes most of the time, from
15 seconds to almost 2 hours, and doesn't follow input size. Example 6 has only
DNA chains, which AlphaFold 3 doesn't search for MSAs, so it finishes in
seconds. The inputs with RNA (examples 7 and 13) run `nhmmer` against the RNA
databases and take over an hour each. Protein searches vary too: examples 2, 8
and 9 took over an hour, while the TetR examples (10 to 12) took about 14
minutes. Stage 2 takes 1 to 3 minutes on one L40S and grows with the number
of tokens.

## Prediction confidence

Scores of the top-ranked prediction, from `output/<name>/<name>_summary_confidences.json`.
Each run made 5 samples from one seed.

| Example | Output name | Ranking score | pTM | ipTM | Fraction disordered | Has clash |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| [`example1`](example1/) | `2PV7` | 0.91 | 0.86 | 0.86 | 0.10 | no |
| [`example2`](example2/) | `barnase_barstar_complex` | 0.93 | 0.94 | 0.93 | 0.00 | no |
| [`example3`](example3/) | `calmodulin_4calcium` | 0.56 | 0.57 | 0.55 | 0.01 | no |
| [`example4`](example4/) | `ERK2_dual_phosphorylated` | 0.92 | 0.90 | – | 0.04 | no |
| [`example5`](example5/) | `KRAS_G12C_sotorasib_covalent` | 0.98 | 0.85 | 0.95 | 0.09 | no |
| [`example6`](example6/) | `methylated_CpG_dsDNA` | 0.82 | 0.82 | 0.82 | 0.00 | no |
| [`example7`](example7/) | `modified_RNA_hairpin` | 0.70 | 0.70 | – | 0.00 | no |
| [`example8`](example8/) | `RNaseB_glycosylated` | 0.90 | 0.93 | 0.89 | 0.00 | no |
| [`example9`](example9/) | `streptavidin_biotin_smiles` | 0.96 | 0.92 | 0.96 | 0.02 | no |
| [`example10`](example10/) | `TetR_dimer_tetO_DNA` | 0.93 | 0.88 | 0.87 | 0.11 | no |
| [`example11`](example11/) | `TetR_dimer_tetracycline` | 0.99 | 0.92 | 0.92 | 0.13 | no |
| [`example12`](example12/) | `TetR_homodimer` | 0.93 | 0.87 | 0.86 | 0.14 | no |
| [`example13`](example13/) | `U1A_RNA_hairpin` | 0.83 | 0.86 | 0.82 | 0.01 | no |
| [`example14`](example14/) | `ubiquitin_monomer` | 0.86 | 0.86 | – | 0.00 | no |

ipTM is shown as – for single-chain inputs (examples 4, 7 and 14), where it
isn't defined.

How to read the scores (from the upstream
[output documentation](https://github.com/google-deepmind/alphafold3/blob/main/docs/output.md)):

- **pTM** scores the whole structure; above 0.5 means the overall fold is
  likely close to the true structure.
- **ipTM** scores the relative positions of the chains; above 0.8 is a
  confident, high-quality prediction, below 0.6 is likely a failed prediction,
  and 0.6 to 0.8 is a grey zone.
- **Ranking score** combines ipTM, pTM, disorder and clashes, and is used to
  pick the top prediction (`<name>_model.cif`).
- **Has clash** is set when a chain has many atoms that overlap another chain.

All predictions except example 3 have ipTM (or pTM, for single chains) of 0.7
or higher, and none has clashes. Example 3 (calmodulin with 4 Ca²⁺) scores
0.57 pTM and 0.55 ipTM. Calmodulin has two domains joined by a flexible
linker, so their relative position is likely uncertain, which would lower
both scores.
