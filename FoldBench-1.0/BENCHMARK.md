# What FoldBench Is and How It Works

This document explains what this repository does, how its pieces fit together, and what role AlphaFold 3 plays in it. It was written by reading the code and data in this repo. For the scientific details, see the paper: Xu et al., *Benchmarking all-atom biomolecular structure prediction with FoldBench*, Nature Communications (2025), doi:10.1038/s41467-025-67127-3.

## TL;DR

FoldBench is a **benchmark**. It is not a structure-prediction model. It provides:

1. **A curated set of test targets** (`targets/*.csv`). These are recently released PDB structures chosen to have **low homology** to anything in the PDB before 2023-01-13, so models can't do well just by memorising their training data.
2. **A harness for running models**. Each model is wrapped in an Apptainer container with a standard preprocess, predict and postprocess interface (`algorithms/`, `run.sh`, `build_apptainer_images.sh`).
3. **A scoring pipeline**. It compares predicted structures to the experimental ground truth using OpenStructure and DockQ, then combines the scores into success rates and LDDT averages (`evaluate.py`, `evaluation/`, `task_score_summary.py`).
4. **A leaderboard** (in `README.md`) comparing AlphaFold 3, Boltz-1/2, Chai-1, HelixFold 3, Protenix, OpenFold 3 (preview) and RoseTTAFold 3.

**AlphaFold 3 is one part of the paper, not the whole thing.** It is one of the models being evaluated, and it is the strongest one in almost every category. AlphaFold 3 also provides the **input format** that the whole benchmark uses. Its code and weights are **not** in this repository. More detail is in [the AlphaFold 3 section](#the-role-of-alphafold-3) below.

---

## 1. The benchmark targets

`targets/` contains nine CSV files, one per task. Each row identifies a PDB biological assembly (e.g. `8tuz-assembly1`) and the chains that make up the interface or monomer to be scored.

| Task file | Rows | What is scored |
|---|---:|---|
| `interface_protein_protein.csv` | 279 | protein–protein interface (chain pair) |
| `interface_antibody_antigen.csv` | 172 | antibody–antigen interface (also lists `antibody_chain`, `antigen_chain`) |
| `interface_protein_ligand.csv` | 558 | protein–small-molecule interface (with CCD `ligand_id`) |
| `interface_protein_peptide.csv` | 51 | protein–peptide interface |
| `interface_protein_rna.csv` | 70 | protein–RNA interface |
| `interface_protein_dna.csv` | 330 | protein–DNA interface |
| `monomer_protein.csv` | 334 | single protein chain |
| `monomer_rna.csv` | 15 | single RNA chain |
| `monomer_dna.csv` | 14 | single DNA chain |

(Row counts come from the CSVs. The README gives 330 protein monomers, but the CSV has 334 rows.)

The ground-truth mmCIF files are **not** stored in git. The README links to a Google Drive archive. Only four example structures are included, under `examples/ground_truths/`.

The main design choice is the low-homology filter against pre-2023-01-13 PDB data. Models whose training data extends past that date (Boltz-2 and RoseTTAFold 3 in the README) may have seen these targets. For that reason the leaderboard marks them with `*` and reports them for reference only.

## 2. Pipeline overview

```
alphafold3_inputs.json  ──►  preprocess.py   ──►  model-specific input
   (AF3 JSON format,            (per model)          (outputs/input/<model>/)
    one entry per target)                                   │
                                                            ▼
                                              make_predictions.sh  (inside Apptainer, GPU)
                                                            │
                                                            ▼
                                              raw predictions  (outputs/prediction/<model>/)
                                                            │
                                                            ▼
                                              postprocess.py
                                               ├─ normalise mmCIF for OST/DockQ
                                               └─ write prediction_reference.csv
                                                  (pdb_id, seed, sample, ranking_score, prediction_path)
                                                            │
                                                            ▼
                                              evaluate.py   ──►  per-sample scores
                                               ├─ OpenStructure `compare-structures` (LDDT, DockQ, TM, GDT, RMSD)
                                               ├─ OpenStructure `compare-ligand-structures` (ligand RMSD, LDDT-PLI)
                                               └─ DockQ v2 (protein–DNA/RNA interfaces)
                                                            │
                                                            ▼
                                              task_score_summary.py  ──►  summary_table.csv
```

`run.sh <algorithm> <gpu_id>` runs this whole chain for each directory in `algorithms/`. `build_apptainer_images.sh` builds `container.sif` from each `container.def`.

### 2.1 Adding a model (`algorithms/<name>/`)

Each model directory must contain the following files (see `algorithms/README.md`):

- `container.def`: an Apptainer recipe for the model environment.
- `preprocess.py`: converts the shared **AlphaFold 3-format** input JSON into the model's own input format.
- `make_predictions.sh`: runs inference.
- `postprocess.py`: cleans the output mmCIFs and writes `prediction_reference.csv`.

The repo ships **only one** model integration: **Protenix**, ByteDance's open-source reproduction of AlphaFold 3. It also vendors the Protenix source under `algorithms/Protenix/Protenix/`. Protenix is configured to run 5 seeds × 5 diffusion samples, with 10 recycles and 200 diffusion steps. The bundled example outputs contain only seed 42.

### 2.2 Scoring (`evaluate.py`, `evaluation/`)

- **Polymer interfaces and monomers**: `ost compare-structures` computes LDDT, TM-score, GDT-TS, RMSD and per-interface DockQ, iRMSD and LRMSD. The row for the target chain pair is picked out of the OST JSON.
- **Protein–ligand**: `ost compare-ligand-structures` computes the ligand RMSD, LDDT-LP and LDDT-PLI for the specific ligand chain.
- **Protein–DNA / protein–RNA**: these are *also* scored with a vendored, modified **DockQ v2** (`evaluation/DockQv2`, `eval_by_dockqv2.py`). It is patched so that modified residues count as polymer rather than ligand. The DockQ success rate for these two tasks comes from the DockQ v2 numbers.

### 2.3 Summary (`task_score_summary.py`)

Each model produces several samples per target. The script picks one per target (or per interface) in one of two ways:

- `--metric_type rank` (**default, used for the leaderboard**): it takes the sample with the highest model-reported `ranking_score`. This is the realistic setting, where the model has to choose its own best answer.
- `--metric_type best`: it takes the sample with the best metric value, which is an oracle upper bound.

The success criteria are:

- **Protein–ligand**: ligand RMSD < 2 Å **and** LDDT-PLI > 0.8.
- **All other interfaces**: DockQ ≥ 0.23, the CAPRI "acceptable" threshold.
- **Monomers**: mean LDDT, with TM-score, GDT-TS and RMSD also reported.

## 3. What you can run from this repo alone

With the `foldbench` conda env (OpenStructure 2.8 and friends), you can re-score the bundled Protenix predictions on the four example targets:

```bash
python evaluate.py --algorithm_name Protenix
python task_score_summary.py --algorithm_names Protenix \
  --targets interface_protein_ligand interface_protein_dna monomer_protein
```

To reproduce the full leaderboard you also need:

- the ground-truth CIFs (Google Drive link in the README),
- an `alphafold3_inputs.json` that covers every target (only a four-target example is included here),
- a container and GPU run for every model.

---

## The role of AlphaFold 3

AlphaFold 3 is **one important part** of FoldBench. It is not the subject of the whole paper. It shows up in three distinct ways.

### 1. One of the models being benchmarked (and the reference point)

FoldBench is a head-to-head comparison of all-atom structure predictors. AlphaFold 3 is one row in the leaderboard. It is the best "strictly valid" model in every interface category, and in all but one monomer category:

| Task (≥ 2023-01 set) | AlphaFold 3 | Next best |
|---|---:|---|
| Protein–protein | 72.93% | 69.96% (OpenFold 3 preview) |
| Antibody–antigen | 47.90% | 34.13% (Protenix) |
| Protein–ligand | 64.90% | 55.04% (Boltz-1) |
| Protein–RNA | 62.32% | 56.90% (Boltz-1) |
| Protein–DNA | 79.18% | 70.97% (Boltz-1) |
| RNA monomer (LDDT) | 0.61 | 0.63 (OpenFold 3 preview, which beats AF3) |
| DNA monomer (LDDT) | 0.53 | 0.51 (OpenFold 3 preview) |

Most of the other models (Protenix, Boltz, Chai-1, HelixFold 3, OpenFold 3) are open reproductions or close relatives of the AlphaFold 3 architecture. A large part of the paper's story is therefore how close the open AF3-style models get to AF3 itself, and where they fall short. Antibody–antigen and protein–ligand are where the gap is largest.

### 2. The benchmark's input format

Every target is described in **AlphaFold 3's input JSON format** (`"dialect": "alphafold3", "version": 2`, with `sequences` of `protein`, `rna`, `dna` and `ligand` entries, CCD codes, and modifications). See `examples/alphafold3_inputs.json`. This is the one shared input for all models. Each other model's `preprocess.py` translates *from* the AF3 format into its own format. AlphaFold 3 can take the file as-is. The `ranking_score` field required in `prediction_reference.csv` also follows AF3's naming for its confidence-based ranking score.

### 3. What is *not* here

- Upstream FoldBench has **no AlphaFold 3 integration**, and none of AlphaFold 3's code or weights are included. Google DeepMind distributes AF3 weights only on request, under restrictive terms, which is the likely reason. The authors ran AF3 separately, and only its scores appear in the README.
- The only model upstream ships is Protenix. `algorithms/AlphaFold3/` in this copy is **our reconstruction** of what the AF3 run most likely looked like (see below). It is not the authors' code.

### Reconstructing the AF3 run (`algorithms/AlphaFold3/`)

The repo contains enough evidence to infer the AF3 run with reasonable confidence:

| Evidence in the repo | What it implies for the AF3 run |
|---|---|
| `examples/alphafold3_inputs.json` is native AF3 input (`dialect: alphafold3`, `version: 2`) | AF3 needs no format conversion. Every other model's `preprocess.py` converts *from* this format. |
| Each input has `modelSeeds: [42, 66, 101, 2024, 8888]`, the same seeds Protenix hard-codes | AF3 ran 5 seeds × 5 diffusion samples (its default) = **25 predictions per target**, matching Protenix's `N_sample=5`. |
| `unpairedMsa`, `pairedMsa` and `templates` are `null` | AF3 ran **its own data pipeline** (jackhmmer/nhmmer MSAs, template search) for each target. No precomputed MSAs were used. |
| The file is a JSON **list** of inputs | It has to be split into one file per target, because `run_alphafold.py` reads a top-level list as an AlphaFold Server job file. The split files are then passed with `--input_dir`. |
| `prediction_reference.csv` = `pdb_id, seed, sample, ranking_score, prediction_path` | This is AF3's `<name>_ranking_scores.csv` (`seed, sample, ranking_score`) plus a name and a path. The leaderboard's "rank" mode (choose by `ranking_score`) is AF3's own top-1 choice. |

The reconstruction follows FoldBench's four-file contract and the conventions of the AF3 v3.0.4 setup in `../vanilla-examples` (module paths, output layout):

- `preprocess.py` splits the benchmark list into `<name>.json` files.
- `make_predictions.sh` runs a single call: `run_alphafold.py --input_dir --db_dir --model_dir --output_dir --num_diffusion_samples=5`.
- `postprocess.py` reads each `<name>_ranking_scores.csv` and points to `seed-<s>_sample-<n>/<name>_seed-<s>_sample-<n>_model.cif`.
- `container.def` layers the scripts on the Bridges-2 AF3 image.

Only the pre- and postprocessing have been tested, and only against a mocked AF3 output tree. Caveats:

- `run.sh` binds only the input JSON and `outputs/`. To use this you would also need to bind the database and weight directories (e.g. `-B /ocean`).
- `make_predictions.sh` runs the CPU-heavy data pipeline and GPU inference in one job. On Bridges-2, use `stage1.sh` and `stage2.sh` in the same directory instead. They split the run the way the vanilla examples do: database search on RM-shared, then inference on GPU-shared. Each Slurm array task handles one target:

  ```bash
  # from the FoldBench root
  N=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' examples/alphafold3_inputs.json)
  sbatch -A <allocation-id> --array=1-$N algorithms/AlphaFold3/stage1.sh   # submits stage2.sh itself
  ```

  When all tasks finish, run `postprocess.py`, `evaluate.py` and `task_score_summary.py`. The exact commands are in the header of `stage2.sh`.
- The low-homology cutoff (2023-01-13) is defined against PDB release dates. It is not tied to AF3's training data specifically.

**In short:** AlphaFold 3 is the strongest competitor that FoldBench measures, and its JSON format is how the benchmark describes its inputs. FoldBench itself is the target set, the run harness and the scoring methodology. These are model-agnostic and apply equally to all eight models on the leaderboard.
