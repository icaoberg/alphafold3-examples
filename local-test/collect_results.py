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

"""Collect the stage 1 data pipeline timings into results.csv.

Usage, from this directory:
  ./collect_results.py [-o results.csv]

Reads every example*/af3-data-*.out written by stage1.sh, adds the node and
start and end times of each job from sacct, writes one row per replicate, and
prints the median and maximum wall time per example.
"""

import argparse
import csv
import re
import statistics
import subprocess
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Seconds spent searching each database, summed over the protein chains.
DATABASES = {
    "uniref90": "uniref90",
    "uniprot": "uniprot_all",
    "mgnify": "mgy_clusters",
    "bfd": "bfd-first_non_consensus",
    "pdb": "pdb_seqres",
}

FIELDS = [
    "example", "replicate", "job_id", "status", "node", "start", "end",
    "elapsed_seconds", "msa_seconds", "template_seconds",
    *(f"{db}_seconds" for db in DATABASES),
    "protein_chains", "unpaired_sequences", "paired_sequences", "templates",
    "log",
]

LOG_NAME = re.compile(r"af3-data-(\d+)_(\d+)\.out$")
REPLICATE = re.compile(r"^Replicate: (\d+)$")
ELAPSED = re.compile(r"^Elapsed time: (\d+):(\d\d):(\d\d)$")
FINISHED = re.compile(r"Finished (?:Jackhmmer|Hmmsearch) \((.+?)\) in "
                      r"([\d.]+) seconds")
MSA = re.compile(r"Getting protein MSAs took ([\d.]+) seconds")
DEDUP = re.compile(r"found (\d+) unpaired sequences, (\d+) paired sequences")
TEMPLATES = re.compile(r"Getting (\d+) protein templates took ([\d.]+) "
                       r"seconds")


def parse(log):
    row = {"log": str(log.relative_to(HERE)), "example": log.parent.name}
    m = LOG_NAME.search(log.name)
    if m:
        row["job_id"] = f"{m.group(1)}_{m.group(2)}"
        row["replicate"] = m.group(2)
    db_seconds = defaultdict(float)
    msa = templates_seconds = 0.0
    chains = unpaired = paired = templates = 0
    elapsed = None
    done = False

    for line in log.read_text(errors="replace").splitlines():
        if m := REPLICATE.match(line):
            row["replicate"] = m.group(1)
        elif m := ELAPSED.match(line):
            h, mi, s = map(int, m.groups())
            elapsed = h * 3600 + mi * 60 + s
        elif m := FINISHED.search(line):
            for db, prefix in DATABASES.items():
                if m.group(1).startswith(prefix):
                    db_seconds[db] += float(m.group(2))
        elif m := MSA.search(line):
            msa += float(m.group(1))
            chains += 1
        elif m := DEDUP.search(line):
            unpaired += int(m.group(1))
            paired += int(m.group(2))
        elif m := TEMPLATES.search(line):
            templates += int(m.group(1))
            templates_seconds += float(m.group(2))
        elif line.startswith("Done running"):
            done = True

    if done:
        row["status"] = "ok"
    elif elapsed is None:
        row["status"] = "incomplete"
    else:
        row["status"] = "failed"

    row["elapsed_seconds"] = "" if elapsed is None else str(elapsed)
    row["msa_seconds"] = f"{msa:.2f}" if chains else ""
    row["template_seconds"] = f"{templates_seconds:.2f}" if chains else ""
    for db in DATABASES:
        row[f"{db}_seconds"] = (f"{db_seconds[db]:.2f}" if db in db_seconds
                                else "")
    row["protein_chains"] = str(chains)
    row["unpaired_sequences"] = str(unpaired) if chains else ""
    row["paired_sequences"] = str(paired) if chains else ""
    row["templates"] = str(templates) if chains else ""
    return row


def add_sacct(rows):
    """Fill in the node, start and end of each job from sacct."""
    jobs = sorted({r["job_id"].split("_")[0] for r in rows if r.get("job_id")})
    if not jobs:
        return
    try:
        out = subprocess.run(
            ["sacct", "-X", "-n", "-P", "-j", ",".join(jobs),
             "-o", "JobID,NodeList,Start,End"],
            capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"sacct failed, leaving node, start and end empty: {e}")
        return
    info = {}
    for line in out.splitlines():
        job_id, node, start, end = line.split("|")
        info[job_id] = (node, start, end)
    for r in rows:
        r["node"], r["start"], r["end"] = info.get(r.get("job_id"), ("", "", ""))


def example_number(name):
    m = re.search(r"\d+$", name or "")
    return int(m.group()) if m else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-o", "--output", default=HERE / "results.csv",
                        type=Path, help="CSV to write (default: results.csv)")
    args = parser.parse_args()

    rows = [parse(log) for log in HERE.glob("example*/af3-data-*.out")]
    rows.sort(key=lambda r: (example_number(r["example"]),
                             int(r.get("replicate") or 0)))
    add_sacct(rows)

    with open(args.output, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} replicates to {args.output}")

    times = defaultdict(list)
    for r in rows:
        if r["status"] == "ok" and r["elapsed_seconds"]:
            times[r["example"]].append(int(r["elapsed_seconds"]) / 60)
    if times:
        print("\nWall time in minutes (successful replicates):\n")
        print(f"{'example':<10}{'n':>4}{'median':>10}{'max':>10}")
        for e in sorted(times, key=example_number):
            t = times[e]
            print(f"{e:<10}{len(t):>4}{statistics.median(t):>10.1f}"
                  f"{max(t):>10.1f}")

    failed = [r for r in rows if r["status"] != "ok"]
    if failed:
        print(f"\n{len(failed)} replicate(s) not ok:")
        for r in failed:
            print(f"  {r['status']:<10} {r['log']}")


if __name__ == "__main__":
    main()
