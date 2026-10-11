"""
postprocess for AlphaFold 3.

RECONSTRUCTION: FoldBench does not ship its AlphaFold 3 integration. This file
is inferred from the Protenix postprocess.py and AlphaFold 3's output layout
(v3.0.1 and later, as produced by the vanilla examples):

    <prediction_dir>/<name>/<name>_ranking_scores.csv          seed,sample,ranking_score
    <prediction_dir>/<name>/seed-<s>_sample-<n>/<name>_seed-<s>_sample-<n>_model.cif

FoldBench's prediction_reference.csv (pdb_id, seed, sample, ranking_score,
prediction_path) is AlphaFold 3's ranking_scores.csv plus a name and a path,
so no score conversion is needed. AlphaFold 3 writes complete mmCIF files
(with an entity category and occupancies), so unlike Protenix the models are
used as-is.

Uses only the standard library, so it runs with the Python in the AF3
container.
"""

import argparse
import csv
import glob
import json
import os


class PostProcess():
    def __init__(self):
        pass

    def postprocess(self, input_dir, prediction_dir, evaluation_dir):
        data = []
        for input_path in sorted(glob.glob(os.path.join(input_dir, "*.json"))):
            with open(input_path, "r") as f:
                pdb_id = json.load(f)["name"]

            ranking_path = os.path.join(prediction_dir, pdb_id, f"{pdb_id}_ranking_scores.csv")
            if not os.path.exists(ranking_path):
                print(f"No predictions for {pdb_id}: {ranking_path} not found")
                continue

            with open(ranking_path, "r") as f:
                for row in csv.DictReader(f):
                    seed, sample = row["seed"], row["sample"]
                    cif_path = os.path.join(
                        prediction_dir, pdb_id, f"seed-{seed}_sample-{sample}",
                        f"{pdb_id}_seed-{seed}_sample-{sample}_model.cif")
                    if not os.path.exists(cif_path):
                        continue
                    data.append({
                        "pdb_id": pdb_id,
                        "seed": seed,
                        "sample": sample,
                        "ranking_score": row["ranking_score"],
                        "prediction_path": cif_path,
                    })

        print(f"Found {len(data)} predictions")
        os.makedirs(evaluation_dir, exist_ok=True)
        with open(os.path.join(evaluation_dir, "prediction_reference.csv"), "w", newline="") as f:
            writer = csv.DictWriter(
                f, fieldnames=["pdb_id", "seed", "sample", "ranking_score", "prediction_path"])
            writer.writeheader()
            writer.writerows(data)


parser = argparse.ArgumentParser()
parser.add_argument(
    "--input_dir", required=True, help="The path to the algorithm input files."
)
parser.add_argument(
    "--prediction_dir", required=True, help="The path to the algorithm predictions."
)
parser.add_argument(
    "--evaluation_dir", required=True, help="The dir with the evaluation files.",
)
args = parser.parse_args()


postprocess = PostProcess()

postprocess.postprocess(args.input_dir, args.prediction_dir, args.evaluation_dir)
