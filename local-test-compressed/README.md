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
local-test it was copied as a directory of many small files and took about
95 of the 110 minutes spent copying. Here the job copies the single
compressed archive `$AF3_DATABASES/mmcif_files.tgz` instead, extracts it on
`$LOCAL` with `tar -xzf`, and deletes the archive once it is extracted. The
other databases are single files and are copied as before.

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
`output/` are ignored by Git, so `results.csv` and this file record the
results.

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

This test hasn't been run yet. Until it is, `results.csv`, `plots/` and the
tables below are the results of [local-test](../local-test/), which copied
`mmcif_files` as a directory, and are the baseline to compare against.
Rerunning `collect_results.py` and `plot_results.py` here replaces them.

What local-test showed:

- **Searching local disk is fast and predictable.** With the databases on
  `$LOCAL`, the AlphaFold 3 data pipeline takes 12 to 14 minutes for most
  protein inputs. The 5 replicates of each example are within about 2 minutes
  of each other. The slowest replicate of any example took 28 minutes.
- **The same searches on Ocean have long tails.** In the
  [vanilla-examples](../vanilla-examples/) run, which read the databases
  straight from Ocean, the median is similar (14 to 20 minutes for most
  examples). But 9 of the 14 examples had at least one replicate that took
  over 30 minutes, and some took up to 3 h 40 min. Local disk removes these
  tails.
- **Copying the databases costs much more than it saves.** A protein input
  copies about 580 GB, which takes about 2 hours (median 1 h 47 min to
  2 h 19 min per example). That is roughly 90% of each job. Across all
  replicates the jobs used 139 hours: 123 hours copying and 15 hours running
  AlphaFold 3. The vanilla-examples stage 1 used 35 hours in total.
- **`mmcif_files` is most of the copy.** It is 233 GB of many small files
  and took a median of 95 minutes (about 40 MB/s). The single-file
  databases copied at 200 to 400 MB/s: `mgy_clusters` (120 GB) in a median
  of 8.5 minutes and `uniprot_all` (102 GB) in 6.5 minutes. This is what
  this test addresses by copying `mmcif_files` as one archive.
- **Inputs without protein gain nothing.** Example 6 (DNA only) searches no
  databases and copies nothing. Example 7 (RNA) copies about 90 GB in
  4 minutes but runs no faster than it did on Ocean (about 5 minutes).

These copy times are from 60 protein jobs copying from Ocean at once, so
they include contention on Ocean and on the nodes and may be pessimistic for
a single job.

### Plots

`plot_results.py` reads `results.csv` and the vanilla-examples stage 1 logs
and draws these into `plots/`:

```bash
./collect_results.py    # writes results.csv, one row per replicate
./plot_results.py       # writes plots/local_vs_ocean.png and total_vs_ocean.png
```

![Total job time: local-test vs vanilla-examples stage 1](plots/total_vs_ocean.png)

The total time of every replicate's job (copying the databases to `$LOCAL`
plus running AlphaFold 3), compared with the stage 1 time of the same input
in vanilla-examples, which read the databases straight from Ocean, on a log
scale. The bar marks the median, and the right column is the ratio of the
two medians. For inputs with protein local-test took 2.9 to 9.9 times as
long (median 2 h to 2 h 44 min per job, against 14 to 46 minutes on Ocean).
Example 6 copies nothing and took the same time, and example 7 took 1.9 times
as long.

![local-test: copy and AlphaFold 3 time, and local disk vs Ocean](plots/local_vs_ocean.png)

On the left is the median time of each job, split into copying the
databases to `$LOCAL` and running AlphaFold 3. On the right is the AlphaFold 3
data pipeline time of every replicate, reading from `$LOCAL` (local-test)
compared with reading from Ocean (vanilla-examples), on a log scale. The bar
marks the median.

### Running times

The times come from each replicate's log. Job is the full elapsed time,
Copy is `Database copy seconds`, and AlphaFold 3 is `AlphaFold 3 seconds`.
Medians and ranges are over the 5 replicates. The Ocean columns are the
stage 1 elapsed times from [vanilla-examples](../vanilla-examples/), which
ran the same inputs without copying, for comparison.

| Example | What it predicts | Job ID | Job median | Job range | Copy median | AlphaFold 3 median | AlphaFold 3 range | Ocean median | Ocean range |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| [`example1`](example1/) | Protein homodimer (PDB 2PV7) | 48937812 | 02:31:36 | 02:30:55–02:38:15 | 02:18:50 | 00:12:49 | 00:12:03–00:13:53 | 00:20:00 | 00:14:02–02:17:51 |
| [`example2`](example2/) | Protein heterodimer (barnase–barstar) | 48937816 | 02:43:45 | 02:23:56–02:45:30 | 02:17:40 | 00:26:02 | 00:25:19–00:27:47 | 00:28:51 | 00:27:07–03:31:22 |
| [`example3`](example3/) | Protein with ions (calmodulin + 4 Ca²⁺) | 48937823 | 02:12:42 | 02:11:56–02:38:35 | 01:58:32 | 00:13:45 | 00:13:09–00:14:12 | 00:46:29 | 00:14:00–01:21:15 |
| [`example4`](example4/) | Phosphorylated protein (ERK2 pThr185/pTyr187) | 48937825 | 02:12:44 | 02:12:10–02:32:47 | 01:58:31 | 00:14:08 | 00:13:36–00:14:13 | 00:15:04 | 00:15:04–00:15:56 |
| [`example5`](example5/) | Covalent ligand (KRAS G12C + sotorasib) | 48937827 | 02:27:47 | 02:26:47–02:35:58 | 02:14:54 | 00:12:49 | 00:11:51–00:12:50 | 00:15:02 | 00:13:46–00:32:13 |
| [`example6`](example6/) | Methylated double-stranded DNA | 48937841 | 00:00:16 | 00:00:16–00:00:17 | 00:00:00 | 00:00:14 | 00:00:13–00:00:14 | 00:00:16 | 00:00:05–00:00:17 |
| [`example7`](example7/) | Modified RNA (tRNA-like fragment) | 48937843 | 00:09:12 | 00:08:52–00:16:25 | 00:04:10 | 00:04:47 | 00:04:39–00:05:02 | 00:04:55 | 00:04:43–00:05:03 |
| [`example8`](example8/) | Glycoprotein (RNase B + N-glycan) | 48937846 | 02:27:12 | 02:08:53–02:37:16 | 02:14:54 | 00:13:58 | 00:12:01–00:14:15 | 00:14:48 | 00:13:52–00:57:53 |
| [`example9`](example9/) | Protein + ligand from SMILES (streptavidin–biotin) | 48937850 | 02:03:50 | 02:03:14–02:04:17 | 01:50:29 | 00:13:19 | 00:12:44–00:13:45 | 00:14:08 | 00:13:53–00:54:07 |
| [`example10`](example10/) | Protein–DNA complex (TetR dimer + tetO) | 48937852 | 02:04:02 | 02:02:50–02:31:47 | 01:50:28 | 00:13:20 | 00:12:20–00:13:51 | 00:14:16 | 00:13:47–00:24:59 |
| [`example11`](example11/) | Protein homodimer + ligands (TetR + tetracycline) | 48937854 | 02:03:48 | 02:02:49–02:04:38 | 01:50:28 | 00:13:17 | 00:12:18–00:14:08 | 00:14:12 | 00:13:37–00:15:04 |
| [`example12`](example12/) | Protein homodimer (TetR) | 48937855 | 02:04:06 | 02:03:48–02:04:40 | 01:50:34 | 00:13:14 | 00:12:40–00:13:37 | 00:16:48 | 00:13:39–01:23:47 |
| [`example13`](example13/) | Protein–RNA complex (U1A + RNA hairpin) | 48937857 | 02:11:50 | 02:11:09–02:57:21 | 01:52:43 | 00:18:24 | 00:18:02–00:19:06 | 00:20:20 | 00:19:00–01:46:56 |
| [`example14`](example14/) | Protein monomer (ubiquitin) | 48937859 | 02:00:15 | 02:00:06–02:34:10 | 01:47:19 | 00:13:30 | 00:12:53–00:13:35 | 00:34:46 | 00:14:18–03:40:03 |

### Database copy times

Per database, over every replicate of local-test that copied it. Sizes are
as `du --apparent-size` reports them. The `mmcif_files` row is the one this
test changes: here it is replaced by copying `mmcif_files.tgz` and extracting
it, which the logs record separately.

| Database | Size | Copies | Median | Range |
| --- | ---: | ---: | ---: | ---: |
| `mmcif_files` | 233G | 60 | 95 min | 81–104 min |
| `mgy_clusters_2022_05.fa` | 120G | 60 | 8.5 min | 4.8–22.7 min |
| `uniprot_all_2021_04.fa` | 102G | 60 | 6.5 min | 5.4–20.0 min |
| `uniref90_2022_05.fa` | 67G | 60 | 3.3 min | 2.5–9.7 min |
| `bfd-first_non_consensus_sequences.fasta` | 17G | 60 | 40 s | 31–121 s |
| `pdb_seqres_2022_09_28.fasta` | 223M | 60 | <1 s | 0–1 s |
| `nt_rna_2023_02_23_clust_seq_id_90_cov_80_rep_seq.fasta` | 76G | 10 | 5.5 min | 3.6–13.8 min |
| `rnacentral_active_seq_id_90_cov_80_linclust.fasta` | 13G | 10 | 39 s | 34–126 s |
| `rfam_14_9_clust_seq_id_90_cov_80_rep_seq.fasta` | 218M | 10 | 1 s | 0–3 s |

`results.csv` also records, per replicate, the time spent searching each
database, the number of MSA sequences and templates found, and the node the
job ran on (from `sacct`). `collect_results.py` prints the median copy and
AlphaFold 3 time per example.
