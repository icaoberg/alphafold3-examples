#!/usr/bin/env python3
"""Generate AF3 inference-only inputs for a token-size sweep.

Each input is a single protein chain of N residues (1 residue = 1 token for
standard amino acids), with empty MSA and templates so it can run with
--run_data_pipeline=false. Two seeds: seed 1 includes JAX compilation (cold),
seed 2 reuses the compiled model (warm).

Usage:
  ./gen_token_inputs.py [-o inputs] [sizes ...]
"""

import argparse
import json
import random
from pathlib import Path

AA = "ACDEFGHIKLMNPQRSTVWY"
DEFAULT_SIZES = [256, 512, 1024, 2048, 3072, 4096, 5120]


def make_input(n, rng):
    seq = "".join(rng.choice(AA) for _ in range(n))
    return {
        "name": f"tokens{n}",
        "modelSeeds": [1, 2],
        "sequences": [{
            "protein": {
                "id": "A",
                "sequence": seq,
                "unpairedMsa": "",
                "pairedMsa": "",
                "templates": [],
            }
        }],
        "dialect": "alphafold3",
        "version": 1,
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("-o", "--outdir", default="inputs", type=Path)
    p.add_argument("sizes", nargs="*", type=int, default=DEFAULT_SIZES)
    args = p.parse_args()

    args.outdir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(0)  # fixed seed so inputs are reproducible
    for n in args.sizes:
        path = args.outdir / f"tokens{n}.json"
        path.write_text(json.dumps(make_input(n, rng), indent=2))
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
