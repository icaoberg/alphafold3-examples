#!/usr/bin/env python3
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only

"""Generate AF3 inference-only inputs for the token-size sweep.

Each input is a single protein chain of N random amino acids. Standard amino
acids are one token each, so the input has exactly N tokens. MSA and templates
are empty, so the input runs with --norun_data_pipeline. Two model seeds:
seed 1 includes JAX compilation (cold), seed 2 reuses it (warm).

By default one input is written for every AlphaFold 3 default compilation
bucket from 256 to 5120 tokens, so each input fills its bucket exactly and no
padding is added.

Usage:
  ./gen_token_inputs.py [-o inputs] [size ...]
"""

import argparse
import json
import random
from pathlib import Path

AA = "ACDEFGHIKLMNPQRSTVWY"

# Default compilation buckets in run_alphafold.py.
DEFAULT_SIZES = [256, 512, 768, 1024, 1280, 1536, 2048, 2560, 3072, 3584,
                 4096, 4608, 5120]


def make_input(n, rng):
    return {
        "name": f"tokens{n}",
        "modelSeeds": [1, 2],
        "sequences": [{
            "protein": {
                "id": "A",
                "sequence": "".join(rng.choice(AA) for _ in range(n)),
                "unpairedMsa": "",
                "pairedMsa": "",
                "templates": [],
            }
        }],
        "dialect": "alphafold3",
        "version": 1,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("-o", "--outdir", default="inputs", type=Path)
    p.add_argument("sizes", nargs="*", type=int, default=DEFAULT_SIZES)
    args = p.parse_args()

    args.outdir.mkdir(parents=True, exist_ok=True)
    for n in args.sizes:
        # One generator per size, so a size's sequence doesn't depend on
        # which other sizes were generated.
        rng = random.Random(n)
        path = args.outdir / f"tokens{n}.json"
        path.write_text(json.dumps(make_input(n, rng), indent=2) + "\n")
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
