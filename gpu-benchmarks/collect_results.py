#!/usr/bin/env python3
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
#
# Written by Ivan Cao-Berg and River Zhu.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 as published by
# the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# SPDX-License-Identifier: GPL-2.0-only

"""Collect the stage 2 GPU benchmark timings into results.csv.

Usage, from this directory:
  ./collect_results.py [-o results.csv]

Reads every example*/af3-s2-*.out written by stage2.sh, writes one row per
run, and prints the median inference time per example and GPU.
"""

import argparse
import csv
import re
import statistics
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent

FIELDS = [
    "example", "gpu", "repeat", "job_id", "status", "elapsed_seconds",
    "inference_seconds", "featurisation_seconds", "attention", "gpu_name",
    "gpu_memory", "node", "start", "log",
]

HEADER = re.compile(r"^Benchmark (example|gpu|gpu name|gpu memory|repeat|"
                    r"attention|node|job id|start): (.*)$")
# Includes JAX compilation, which happens on the first call.
INFERENCE = re.compile(r"^Running model inference with seed \d+ took "
                       r"([\d.]+) seconds\.$")
FEATURISATION = re.compile(r"^Featurising data with \d+ seed\(s\) took "
                           r"([\d.]+) seconds\.$")
ELAPSED = re.compile(r"^Elapsed seconds: (\d+)$")


def parse(log):
    row = {"log": str(log.relative_to(HERE))}
    inference = []
    featurisation = []
    elapsed = None
    done = False
    oom = False
    timeout = False

    for line in log.read_text(errors="replace").splitlines():
        if m := HEADER.match(line):
            row[m.group(1).replace(" ", "_")] = m.group(2).strip()
        elif m := INFERENCE.match(line):
            inference.append(float(m.group(1)))
        elif m := FEATURISATION.match(line):
            featurisation.append(float(m.group(1)))
        elif m := ELAPSED.match(line):
            # Keep the last one if there are several.
            elapsed = int(m.group(1))
        elif line.startswith("Done running"):
            done = True
        elif "RESOURCE_EXHAUSTED" in line or "out of memory" in line.lower():
            oom = True
        elif "DUE TO TIME LIMIT" in line:
            timeout = True

    if done:
        row["status"] = "ok"
    elif timeout:
        row["status"] = "timeout"
    elif oom:
        row["status"] = "oom"
    elif elapsed is None:
        row["status"] = "incomplete"
    else:
        row["status"] = "failed"

    # Multiple seeds run one after another, so their times add up.
    row["inference_seconds"] = f"{sum(inference):.2f}" if inference else ""
    row["featurisation_seconds"] = (f"{sum(featurisation):.2f}"
                                    if featurisation else "")
    row["elapsed_seconds"] = "" if elapsed is None else str(elapsed)
    return row


def example_number(name):
    m = re.search(r"\d+$", name or "")
    return int(m.group()) if m else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-o", "--output", default=HERE / "results.csv",
                        type=Path, help="CSV to write (default: results.csv)")
    args = parser.parse_args()

    rows = [parse(log) for log in HERE.glob("example*/af3-s2-*.out")]
    rows.sort(key=lambda r: (example_number(r.get("example")), r.get("gpu", ""),
                             int(r.get("repeat") or 0)))

    with open(args.output, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} runs to {args.output}")

    # Median inference seconds (and number of successful runs) per example
    # and GPU.
    times = defaultdict(list)
    for r in rows:
        if r["status"] == "ok" and r["inference_seconds"]:
            times[r["example"], r["gpu"]].append(float(r["inference_seconds"]))
    failed = [r for r in rows if r["status"] != "ok"]

    gpus = sorted({r.get("gpu", "") for r in rows})
    examples = sorted({r.get("example", "") for r in rows}, key=example_number)
    if gpus and examples:
        print("\nMedian inference seconds (successful runs):\n")
        print(f"{'example':<10}" + "".join(f"{g:>16}" for g in gpus))
        for e in examples:
            cells = []
            for g in gpus:
                t = times.get((e, g))
                cells.append(f"{statistics.median(t):>11.1f} (n={len(t)})"
                             if t else f"{'-':>16}")
            print(f"{e:<10}" + "".join(cells))

    if failed:
        print(f"\n{len(failed)} run(s) not ok:")
        for r in failed:
            print(f"  {r['status']:<10} {r['log']}")


if __name__ == "__main__":
    main()
