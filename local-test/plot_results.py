#!/usr/bin/env python3
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only

"""Plot the local-test results against the vanilla-examples stage 1 run.

Usage, from this directory (after ./collect_results.py):
  ./plot_results.py

Reads results.csv (written by collect_results.py) and, for comparison, the
newest ../vanilla-examples/example*/af3-data-<jobid>_<n>.out log of every
replicate, where the data pipeline read the databases straight from Ocean.

Writes:
  plots/local_vs_ocean.png  left: median time per example spent copying the
                            databases to $LOCAL and running AlphaFold 3;
                            right: AlphaFold 3 time per replicate reading
                            from $LOCAL vs from Ocean, log scale
  plots/total_vs_ocean.png  total job time per replicate (copy + AlphaFold 3)
                            vs the vanilla-examples stage 1 time, log scale
"""

import csv
import re
import statistics
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.ticker import FuncFormatter  # noqa: E402

HERE = Path(__file__).resolve().parent
VANILLA = HERE.parent / "vanilla-examples"
OUT = HERE / "plots"

COPY = "#2a78d6"     # categorical slot 1: copying to $LOCAL
AF3 = "#eb6834"      # categorical slot 2: running AlphaFold 3
INK = "#0b0b0b"      # text and median marks
MUTED = "#52514e"    # secondary text
GRID = "#e4e3df"


def number(name):
    return int(re.search(r"\d+$", name).group())


def load_local():
    """{example: {"copy": [s, ...], "alphafold": [s, ...]}} from results.csv."""
    out = defaultdict(lambda: defaultdict(list))
    with open(HERE / "results.csv") as f:
        for r in csv.DictReader(f):
            if r["status"] == "ok":
                out[r["example"]]["copy"].append(int(r["copy_seconds"]))
                out[r["example"]]["alphafold"].append(
                    int(r["alphafold_seconds"]))
    return out


def load_local_total():
    """{example: [s, ...]}: total elapsed job time per replicate."""
    out = defaultdict(list)
    with open(HERE / "results.csv") as f:
        for r in csv.DictReader(f):
            if r["status"] == "ok":
                out[r["example"]].append(int(r["elapsed_seconds"]))
    return out


def load_ocean():
    """{example: [s, ...]}: vanilla-examples stage 1 elapsed time per
    replicate, keeping the newest log of each replicate."""
    out = {}
    for ex in VANILLA.glob("example*/"):
        reps = {}
        for p in sorted(ex.glob("af3-data-*_*.out"),
                        key=lambda p: p.stat().st_mtime):
            m = re.search(r"^Elapsed time: (\d+):(\d+):(\d+)",
                          p.read_text(errors="replace"), re.M)
            if m:
                h, mi, s = map(int, m.groups())
                reps[re.search(r"_(\d+)\.out$", p.name).group(1)] = (
                    h * 3600 + mi * 60 + s)
        if reps:
            out[ex.name] = list(reps.values())
    return out


def style(ax):
    ax.grid(True, axis="x", color=GRID, lw=0.8)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(MUTED)
    ax.tick_params(colors=MUTED, labelcolor=INK)


def hms(seconds, _pos=None):
    if seconds < 60:
        return f"{seconds:.0f} s"
    if seconds < 3600:
        return f"{seconds / 60:.0f} min"
    return f"{seconds / 3600:g} h"


def plot(local, ocean):
    names = sorted(local, key=number, reverse=True)  # example1 at the top
    fig, (left, right) = plt.subplots(
        1, 2, figsize=(11, 6.6), sharey=True,
        gridspec_kw={"width_ratios": [1, 1.1]})

    # Left: where the job's time goes, median of the 5 replicates.
    for y, n in enumerate(names):
        copy = statistics.median(local[n]["copy"]) / 60
        af3 = statistics.median(local[n]["alphafold"]) / 60
        left.barh(y, copy, height=0.6, color=COPY, edgecolor="white", lw=2,
                  label="Copy databases to $LOCAL" if y == 0 else None)
        left.barh(y, af3, left=copy, height=0.6, color=AF3, edgecolor="white",
                  lw=2, label="Run AlphaFold 3" if y == 0 else None)
        total = copy + af3
        left.annotate(f"{total:.0f} min" if total >= 1 else "<1 min", (total, y),
                      xytext=(4, 0), textcoords="offset points",
                      va="center", fontsize=8, color=MUTED)
    left.set_xlim(0, 185)
    left.set_xlabel("Median minutes per job")
    left.set_yticks(range(len(names)), names)
    left.set_title("Where the time goes", loc="left", color=INK)
    style(left)
    left.legend(loc="upper left", bbox_to_anchor=(0, -0.1), ncol=2,
                frameon=False, fontsize=9)

    # Right: data pipeline time per replicate, local disk vs Ocean.
    for y, n in enumerate(names):
        for vals, color, dy, label in (
                (local[n]["alphafold"], AF3, 0.15, "Databases on $LOCAL"),
                (ocean.get(n, []), MUTED, -0.15,
                 "Databases on Ocean (vanilla-examples)")):
            if not vals:
                continue
            right.plot(vals, [y + dy] * len(vals), "o", ms=6, color=color,
                       alpha=0.8, mec="white", mew=1,
                       label=label if y == 0 else None)
            right.plot(statistics.median(vals), y + dy, "|", ms=12, mew=2,
                       color=INK, label="Median" if y == 0 and dy < 0
                       else None)
    right.set_xscale("log")
    right.set_xticks([10, 60, 300, 900, 3600, 14400])
    right.xaxis.set_major_formatter(FuncFormatter(hms))
    right.minorticks_off()
    right.set_xlabel("AlphaFold 3 data pipeline time per replicate "
                     "(log scale)")
    right.set_title("Data pipeline: local disk vs Ocean", loc="left",
                    color=INK)
    style(right)
    right.legend(loc="upper left", bbox_to_anchor=(0, -0.1), ncol=2,
                 frameon=False, fontsize=9)

    fig.suptitle("Local test: copying the databases to $LOCAL first "
                 "(RM-shared, 32 cores, 5 replicates)",
                 x=0.01, ha="left", color=INK, fontsize=12)
    fig.tight_layout()
    fig.savefig(OUT / "local_vs_ocean.png", dpi=200)
    plt.close(fig)


def plot_total(total, ocean):
    names = sorted(total, key=number, reverse=True)  # example1 at the top
    fig, ax = plt.subplots(figsize=(8.5, 6.6))
    for y, n in enumerate(names):
        for vals, color, dy, label in (
                (total[n], COPY, 0.15,
                 "Local test: copy to $LOCAL + AlphaFold 3"),
                (ocean.get(n, []), MUTED, -0.15,
                 "vanilla-examples stage 1 (databases on Ocean)")):
            if not vals:
                continue
            ax.plot(vals, [y + dy] * len(vals), "o", ms=6, color=color,
                    alpha=0.8, mec="white", mew=1,
                    label=label if y == 0 else None)
            ax.plot(statistics.median(vals), y + dy, "|", ms=12, mew=2,
                    color=INK, label="Median" if y == 0 and dy < 0 else None)
        if ocean.get(n):
            ratio = statistics.median(total[n]) / statistics.median(ocean[n])
            ax.annotate(f"{ratio:.1f}\u00d7", (1, y),
                        xycoords=("axes fraction", "data"), xytext=(6, 0),
                        textcoords="offset points", va="center", fontsize=8,
                        color=MUTED)
    ax.annotate("local / Ocean\n(median)", (1, len(names) - 0.4),
                xycoords=("axes fraction", "data"), xytext=(6, 0),
                textcoords="offset points", va="bottom", fontsize=8,
                color=MUTED)
    ax.set_xscale("log")
    ax.set_xticks([10, 60, 300, 900, 3600, 14400])
    ax.xaxis.set_major_formatter(FuncFormatter(hms))
    ax.minorticks_off()
    ax.set_yticks(range(len(names)), names)
    ax.set_xlabel("Total job time per replicate (log scale)")
    style(ax)
    ax.legend(loc="upper left", bbox_to_anchor=(0, -0.1), ncol=2,
              frameon=False, fontsize=9)
    fig.suptitle("Total time: local test vs vanilla-examples stage 1 "
                 "(RM-shared, 32 cores, 5 replicates)",
                 x=0.01, ha="left", color=INK, fontsize=12)
    fig.tight_layout()
    fig.savefig(OUT / "total_vs_ocean.png", dpi=200)
    plt.close(fig)


def main():
    local = load_local()
    if not local:
        raise SystemExit("no results in results.csv; run ./collect_results.py")
    OUT.mkdir(exist_ok=True)
    ocean = load_ocean()
    plot(local, ocean)
    plot_total(load_local_total(), ocean)
    for p in sorted(OUT.glob("*.png")):
        print(p.relative_to(HERE))


if __name__ == "__main__":
    main()
