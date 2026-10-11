"""
preprocess for AlphaFold 3.

RECONSTRUCTION: FoldBench does not ship its AlphaFold 3 integration. This file
is inferred from examples/alphafold3_inputs.json and the Protenix integration.

The benchmark input is already in AlphaFold 3's own JSON dialect, so no format
conversion is needed. The one change is splitting it: the benchmark file is a
JSON *list* of inputs, but run_alphafold.py reads a top-level list as an
AlphaFold Server job file, not as alphafold3-dialect inputs. So each target is
written to its own <name>.json in input_dir, which is then passed to
run_alphafold.py with --input_dir.

The modelSeeds in each input (42, 66, 101, 2024, 8888, the same seeds the
Protenix integration hard-codes) are kept as-is, so AlphaFold 3 runs 5 seeds.
"""

import argparse
import json
import os


class PreProcess():
    def __init__(self):
        super().__init__()

    def preprocess(self, af3_input_json_path, input_dir):
        """
        af3_input_json_path: path to the af3 input json file
        input_dir: path to the input directory for the algorithm
        """
        with open(af3_input_json_path, "r") as f:
            folding_inputs = json.load(f)

        os.makedirs(input_dir, exist_ok=True)
        for folding_input in folding_inputs:
            with open(os.path.join(input_dir, f"{folding_input['name']}.json"), "w") as f:
                json.dump(folding_input, f, indent=4)
        print(
            "{} folding inputs written to {}.".format(len(folding_inputs), input_dir)
        )


parser = argparse.ArgumentParser()
parser.add_argument(
    "--af3_input_json",
    help="The path to the input .json file.",
)
parser.add_argument(
    "--input_dir",
    help="The path to write one AlphaFold 3 input .json file per target.",
)
args = parser.parse_args()

preprocess = PreProcess()
preprocess.preprocess(args.af3_input_json, args.input_dir)
