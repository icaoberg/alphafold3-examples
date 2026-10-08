# Local test: data pipeline

Runs the AlphaFold 3 data pipeline (MSA and template search) for 14 examples on
Bridges-2 with AlphaFold 3 v3.0.4. Each example runs as one Slurm job, using
the `stage1.sh` script in its directory:

| Stage | Partition | Resources |
| --- | --- | --- |
| 1: data pipeline | `RM-shared` | 32 cores (about 64 GB of memory) |

The job logs (`af3-data-<jobid>_N.out`) and the `output/` directories are
written to each example directory.

## Run all examples

`submit.sh` submits stage 1 for every example as a job array of 5 replicates:

```bash
./submit.sh -A <allocation-id>            # all examples, replicates 1-5
./submit.sh -A <allocation-id> -n         # dry run: print the sbatch commands
./submit.sh -A <allocation-id> -r 1 example1 example2
```

Replicates that already have data pipeline output, and examples with jobs
still queued or running, are skipped, so rerunning the same command retries
only failed replicates. See the comments in `submit.sh` for all options.

## Examples

| Example | What it predicts |
| --- | --- |
| [`example1`](example1/) | Protein homodimer (PDB 2PV7) |
| [`example2`](example2/) | Protein heterodimer (barnase–barstar) |
| [`example3`](example3/) | Protein with ions (calmodulin + 4 Ca²⁺) |
| [`example4`](example4/) | Phosphorylated protein (ERK2 pThr185/pTyr187) |
| [`example5`](example5/) | Covalent ligand (KRAS G12C + sotorasib) |
| [`example6`](example6/) | Methylated double-stranded DNA |
| [`example7`](example7/) | Modified RNA (tRNA-like fragment) |
| [`example8`](example8/) | Glycoprotein (RNase B + N-glycan) |
| [`example9`](example9/) | Protein + ligand from SMILES (streptavidin–biotin) |
| [`example10`](example10/) | Protein–DNA complex (TetR dimer + tetO) |
| [`example11`](example11/) | Protein homodimer + ligands (TetR + tetracycline) |
| [`example12`](example12/) | Protein homodimer (TetR) |
| [`example13`](example13/) | Protein–RNA complex (U1A + RNA hairpin) |
| [`example14`](example14/) | Protein monomer (ubiquitin) |

## Results

Once the jobs finish, collect the timings and plot them:

```bash
./collect_results.py    # writes results.csv, one row per replicate
./plot_results.py       # writes plots/
```

`collect_results.py` reads the job logs and adds each job's node and start
and end times from `sacct`. `results.csv` records, per replicate, the wall
time, the time spent searching each database, and the MSA depth.

| Plot | What it shows |
| --- | --- |
| [`plots/walltime.png`](plots/walltime.png) | Wall time of every replicate per example |
| [`plots/databases.png`](plots/databases.png) | Time spent searching each database |
| [`plots/timeline.png`](plots/timeline.png) | When each replicate ran, and on which node |

In the run from 2026-10-07, all 70 replicates finished. Most examples take
about 15 minutes, but 18 replicates took 1 to 4.7 hours on the same inputs.
The extra time is spent in the jackhmmer searches of UniRef90, UniProt and
MGnify; template search takes seconds.
