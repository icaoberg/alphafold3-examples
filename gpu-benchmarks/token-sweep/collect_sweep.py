#!/usr/bin/env python3
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only

"""Collect token-sweep timings into sweep_results.csv.

Usage, from this directory:
  ./collect_sweep.py [-o sweep_results.csv]

Reads logs/af3-sweep-*.out written by sweep.sh. Seed 1 includes JAX
compilation (cold); seed 2 is compile-free (warm), comparable to DeepMind's
published timings.
"""

import argparse
import csv
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

# DeepMind docs/performance.md, compile-free seconds.
OFFICIAL = {
    1024: (62, 34), 2048: (275, 144), 3072: (703, 367),
    4096: (1434, 774), 5120: (2547, 1416),
}

FIELDS = [
    "tokens", "gpu", "repeat", "memprofile", "status", "cold_seconds",
    "warm_seconds", "compile_seconds_est", "peak_gpu_mem_mib",
    "a100_official", "h100_official", "elapsed_seconds", "gpu_name",
    "node", "job_id", "log",
]

HEADER = re.compile(r"^Benchmark (tokens|gpu|gpu name|repeat|memprofile|"
                    r"node|job id): (.*)$")
INFERENCE = re.compile(r"Running model inference with seed (\d+) took "
                       r"([\d.]+) seconds")
PEAK = re.compile(r"^Peak GPU memory MiB: (\d+)")
ELAPSED = re.compile(r"^Elapsed seconds: (\d+)$")


def parse(log):
    row = {"log": str(log.relative_to(HERE))}
    seeds = {}
    done = oom = timeout = False
    for line in log.read_text(errors="replace").splitlines():
        if m := HEADER.match(line):
            row[m.group(1).replace(" ", "_")] = m.group(2).strip()
        elif m := INFERENCE.search(line):
            seeds[int(m.group(1))] = float(m.group(2))
        elif m := PEAK.match(line):
            row["peak_gpu_mem_mib"] = m.group(1)
        elif m := ELAPSED.match(line):
            row["elapsed_seconds"] = m.group(1)
        elif line.startswith("Done running"):
            done = True
        elif "RESOURCE_EXHAUSTED" in line or "out of memory" in line.lower():
            oom = True
        elif "DUE TO TIME LIMIT" in line:
            timeout = True

    row["status"] = ("ok" if done else "oom" if oom else
                     "timeout" if timeout else "incomplete")
    cold, warm = seeds.get(1), seeds.get(2)
    row["cold_seconds"] = f"{cold:.1f}" if cold is not None else ""
    row["warm_seconds"] = f"{warm:.1f}" if warm is not None else ""
    if cold is not None and warm is not None:
        row["compile_seconds_est"] = f"{cold - warm:.1f}"
    n = int(row.get("tokens") or 0)
    if n in OFFICIAL:
        row["a100_official"], row["h100_official"] = OFFICIAL[n]
    return row


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("-o", "--output", default=HERE / "sweep_results.csv",
                   type=Path)
    args = p.parse_args()

    rows = [parse(f) for f in sorted((HERE / "logs").glob("af3-sweep-*.out"))]
    rows.sort(key=lambda r: (r.get("gpu", ""), r.get("memprofile", ""),
                             int(r.get("tokens") or 0),
                             int(r.get("repeat") or 0)))
    with open(args.output, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print(f"Wrote {len(rows)} runs to {args.output}\n")

    print(f"{'tokens':>7} {'gpu':>9} {'mem':>4} {'status':>10} {'cold':>8} "
          f"{'warm':>8} {'A100':>6} {'H100':>6} {'peakMiB':>8}")
    for r in rows:
        print(f"{r.get('tokens',''):>7} {r.get('gpu',''):>9} "
              f"{r.get('memprofile',''):>4} {r['status']:>10} "
              f"{r['cold_seconds']:>8} {r['warm_seconds']:>8} "
              f"{str(r.get('a100_official','')):>6} "
              f"{str(r.get('h100_official','')):>6} "
              f"{r.get('peak_gpu_mem_mib',''):>8}")


if __name__ == "__main__":
    main()
