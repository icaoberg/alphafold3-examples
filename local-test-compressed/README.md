# Local test (compressed): data pipeline

Runs the AlphaFold 3 data pipeline (MSA and template search) for 14 examples on
Bridges-2 with AlphaFold 3 v3.0.4. Each example runs as one Slurm job, using
the `stage1.sh` script in its directory:

| Stage | Partition | Resources | Ran |
| --- | --- | --- | --- |
| 1: data pipeline | `RM-shared` | 32 cores (about 64 GB of memory) | not yet |

This is a variant of [local-test](../local-test/). Before running
AlphaFold 3, each job copies the databases its input needs from Ocean to
node-local storage (`$LOCAL`) and sets `AF3_DATABASES` to the copy, so the
searches read from local disk. The difference is `mmcif_files`: in
local-test it was copied as a directory of many small files. Here the job
copies the single compressed archive `$AF3_DATABASES/mmcif_files.tgz`
instead, extracts it on `$LOCAL` with `tar -xzf`, and deletes the archive
once it is extracted. The other databases are single files and are copied
as before.

Protein inputs need about 580 GB on `$LOCAL` (the five protein databases and
the extracted `mmcif_files`), plus room for the archive while it is
extracted, and RNA inputs another 95 GB.

The job logs (`af3-data-<jobid>_N.out`) and the `output/` directories are
written to each example directory. Each log records the time spent copying
each database (`Copied <database> (<size>) in <seconds> seconds`, where
`mmcif_files` appears as `mmcif_files.tgz`), the time spent extracting the
archive (`Extracted mmcif_files.tgz (<size>) in <seconds> seconds`), the
total copy time including the extraction (`Database copy seconds`), and the
time spent running AlphaFold 3 (`AlphaFold 3 seconds`). The logs and
`output/` are ignored by Git.

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

## Collect results

After the jobs finish, `collect_results.py` reads the logs and
`plot_results.py` draws the plots into `plots/`:

```bash
./collect_results.py    # writes results.csv, one row per replicate
./plot_results.py       # writes plots/local_vs_ocean.png and total_vs_ocean.png
```
