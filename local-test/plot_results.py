#!/usr/bin/env python3
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only

"""Plot the stage 1 data pipeline timings from results.csv.

Usage, from this directory (after ./collect_results.py):
  ./plot_results.py

Writes:
  plots/walltime.png   wall time of every replicate per example
  plots/databases.png  time spent searching each database, per replicate
  plots/timeline.png   when each replicate ran, to show how many searches
                       ran at the same time
"""

import csv
import re
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = HERE / "plots"

DATABASES = ["uniref90", "uniprot", "mgnify", "bfd", "pdb"]
LABEL = {"uniref90": "UniRef90", "uniprot": "UniProt", "mgnify": "MGnify",
         "bfd": "BFD", "pdb": "PDB seqres\n(templates)"}
COLOR = {"uniref90": "tab:blue", "uniprot": "tab:orange",
         "mgnify": "tab:red", "bfd": "tab:green", "pdb": "tab:purple"}


def num(x):
    return float(x) if x not in ("", None) else None


def example_number(name):
    m = re.search(r"\d+$", name)
    return int(m.group()) if m else 0


def load():
    with open(HERE / "results.csv") as f:
        rows = [r for r in csv.DictReader(f) if r["status"] == "ok"]
    return sorted(rows, key=lambda r: (example_number(r["example"]),
                                       int(r["replicate"])))


def plot_walltime(rows):
    by_example = defaultdict(list)
    for r in rows:
        by_example[r["example"]].append(num(r["elapsed_seconds"]) / 60)
    examples = sorted(by_example, key=example_number)

    fig, ax = plt.subplots(figsize=(8, 4.5))
    for i, e in enumerate(examples):
        t = sorted(by_example[e])
        offsets = [(j - (len(t) - 1) / 2) * 0.08 for j in range(len(t))]
        ax.plot([i + o for o in offsets], t, "o", color="tab:blue",
                alpha=0.7)
        median = t[len(t) // 2]
        ax.plot([i - 0.3, i + 0.3], [median, median], "-", color="black",
                lw=2)
    ax.set_yscale("log")
    ax.set_xticks(range(len(examples)))
    ax.set_xticklabels([e.replace("example", "") for e in examples])
    ax.set_xlabel("Example")
    ax.set_ylabel("Wall time (minutes)")
    ax.set_title("AlphaFold 3 data pipeline wall time, 5 replicates "
                 "(32 cores, RM-shared)")
    ax.text(0.01, 0.97, "line = median", transform=ax.transAxes, va="top",
            fontsize=8, color="dimgray")
    ax.grid(True, which="both", axis="y", alpha=0.3)
    fig.tight_layout()
    fig.savefig(OUT / "walltime.png", dpi=200)
    plt.close(fig)


def plot_databases(rows):
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for i, db in enumerate(DATABASES):
        t = [num(r[f"{db}_seconds"]) / 60 for r in rows
             if num(r[f"{db}_seconds"])]
        if not t:
            continue
        ax.boxplot(t, positions=[i], widths=0.5, showfliers=False)
        offsets = [((j % 7) - 3) * 0.04 for j in range(len(t))]
        ax.plot([i + o for o in offsets], t, "o", color=COLOR[db], alpha=0.5,
                ms=4)
    ax.set_yscale("log")
    ax.set_xticks(range(len(DATABASES)))
    ax.set_xticklabels([LABEL[db] for db in DATABASES])
    ax.set_ylabel("Search time per replicate (minutes)")
    ax.set_title("Time spent searching each database")
    ax.grid(True, which="both", axis="y", alpha=0.3)
    fig.tight_layout()
    fig.savefig(OUT / "databases.png", dpi=200)
    plt.close(fig)


def plot_timeline(rows):
    runs = [r for r in rows if r["start"] and r["end"]]
    if not runs:
        return
    runs.sort(key=lambda r: (r["start"], example_number(r["example"]),
                             int(r["replicate"])))
    cmap = plt.get_cmap("viridis")
    vmax = max(num(r["elapsed_seconds"]) for r in runs) / 3600

    fig, ax = plt.subplots(figsize=(9, 9))
    first = last = None
    for i, r in enumerate(runs):
        start = mdates.date2num(datetime.fromisoformat(r["start"]))
        end = mdates.date2num(datetime.fromisoformat(r["end"]))
        first = start if first is None else min(first, start)
        last = end if last is None else max(last, end)
        hours = num(r["elapsed_seconds"]) / 3600
        ax.barh(i, end - start, left=start, height=0.8,
                color=cmap(hours / vmax))
        ax.text(end, i, f" {r['node']}", va="center", fontsize=6,
                color="dimgray")
    # Leave room on the right for the node labels.
    ax.set_xlim(first, last + (last - first) * 0.08)
    ax.xaxis_date()
    ax.set_yticks(range(len(runs)))
    ax.set_yticklabels([f"{r['example'].replace('example', 'ex')} "
                        f"r{r['replicate']}" for r in runs], fontsize=6)
    ax.invert_yaxis()
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    ax.set_xlabel(f"Time on {runs[0]['start'][:10]}")
    ax.set_title("When each replicate ran (label = node)")
    sm = plt.cm.ScalarMappable(cmap=cmap, norm=plt.Normalize(0, vmax))
    fig.colorbar(sm, ax=ax, label="Wall time (hours)", pad=0.08)
    ax.grid(True, axis="x", alpha=0.3)
    fig.tight_layout()
    fig.savefig(OUT / "timeline.png", dpi=200)
    plt.close(fig)


def main():
    OUT.mkdir(exist_ok=True)
    rows = load()
    plot_walltime(rows)
    plot_databases(rows)
    plot_timeline(rows)
    print(f"Wrote plots for {len(rows)} replicates to {OUT}")


if __name__ == "__main__":
    main()
