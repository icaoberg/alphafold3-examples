#!/usr/bin/env python3
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only

"""Plot the vanilla-examples results from the job logs and outputs.

Usage, from this directory (after the stage 1 and stage 2 jobs finish):
  ./plot_results.py

Reads, for each example*/ directory, the newest af3-data-<jobid>_<n>.out and
af3-inference-<jobid>_<n>.out log of every replicate, and
output/replicate-<n>/<name>/<name>_summary_confidences.json.

Writes:
  plots/stage1_time.png   stage 1 (data pipeline) elapsed time per example,
                          every replicate plus the median, log scale
  plots/stage2_tokens.png stage 2 model inference time vs input tokens,
                          with AlphaFold 3's padding sizes
  plots/confidence.png    ipTM (pTM for single chains) of the top-ranked
                          prediction per example, with the upstream
                          confidence bands
"""

import json
import re
import statistics
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.ticker import FuncFormatter  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = HERE / "plots"

SERIES = "#2a78d6"   # one series per chart, so one hue
INK = "#0b0b0b"      # text and median marks
MUTED = "#52514e"    # secondary text, reference lines
GRID = "#e4e3df"

# Token counts AlphaFold 3 pads inputs up to (the default --buckets).
BUCKETS = [256, 512, 768]


def elapsed(text):
    m = re.search(r"^Elapsed time: (\d+):(\d+):(\d+)", text, re.M)
    if not m:
        return None
    h, mi, s = map(int, m.groups())
    return h * 3600 + mi * 60 + s


def logs(example, kind):
    """{replicate: log text}, keeping the newest log of each replicate."""
    out = {}
    paths = sorted(example.glob(f"af3-{kind}-*_*.out"),
                   key=lambda p: p.stat().st_mtime)
    for p in paths:
        rep = int(re.search(r"_(\d+)\.out$", p.name).group(1))
        out[rep] = p.read_text(errors="replace")
    return out


def load():
    examples = sorted(HERE.glob("example*/"),
                      key=lambda p: int(re.search(r"\d+$", p.name).group()))
    rows = []
    for ex in examples:
        conf = [json.loads(p.read_text()) for p in
                sorted(ex.glob("output/replicate-*/*/*_summary_confidences.json"))]
        if not conf:
            continue
        stage1 = [elapsed(t) for t in logs(ex, "data").values()]
        model = []
        for t in logs(ex, "inference").values():
            m = re.search(r"Running model inference with seed \d+ took "
                          r"([\d.]+) seconds", t)
            if m:
                model.append(float(m.group(1)))
        single = len(conf[0]["chain_ptm"]) == 1
        key = "ptm" if single else "iptm"
        rows.append(dict(
            name=ex.name,
            tokens=len(conf[0]["chain_ids"]),
            stage1=[s for s in stage1 if s is not None],
            model=model,
            score=statistics.median(c[key] for c in conf),
            metric="pTM" if single else "ipTM",
        ))
    return rows


def style(ax):
    ax.grid(True, color=GRID, lw=0.8)
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


def plot_stage1(rows):
    rows = sorted(rows, key=lambda r: statistics.median(r["stage1"]))
    fig, ax = plt.subplots(figsize=(8, 5.5))
    for y, r in enumerate(rows):
        ax.plot(r["stage1"], [y] * len(r["stage1"]), "o", ms=7, color=SERIES,
                alpha=0.75, mec="white", mew=1,
                label="Replicate" if y == 0 else None)
        ax.plot(statistics.median(r["stage1"]), y, "|", ms=18, mew=2.5,
                color=INK, label="Median" if y == 0 else None)
    ax.set_xscale("log")
    ax.set_xticks([10, 60, 300, 900, 1800, 3600, 7200, 14400])
    ax.xaxis.set_major_formatter(FuncFormatter(hms))
    ax.minorticks_off()
    ax.set_yticks(range(len(rows)), [r["name"] for r in rows])
    ax.set_xlabel("Stage 1 elapsed time (log scale)")
    ax.set_title("Stage 1 (data pipeline, RM-shared, 32 cores): "
                 "time per replicate", loc="left", color=INK)
    style(ax)
    ax.legend(loc="lower right", frameon=False)
    fig.tight_layout()
    fig.savefig(OUT / "stage1_time.png", dpi=200)
    plt.close(fig)


def plot_stage2(rows):
    fig, ax = plt.subplots(figsize=(8, 4.5))
    for b in BUCKETS:
        ax.axvline(b, color=MUTED, ls="--", lw=1)
        ax.text(b, 1.0, f" padded to {b}", transform=ax.get_xaxis_transform(),
                va="top", ha="right", rotation=90, fontsize=8, color=MUTED)
    for r in rows:
        ax.plot([r["tokens"]] * len(r["model"]), r["model"], "o", ms=7,
                color=SERIES, alpha=0.75, mec="white", mew=1)
    # One label per padding size, centred over its range and above its group
    # of examples, since they sit too close together to label one by one.
    for lo, hi in zip([0] + BUCKETS, BUCKETS):
        group = [r for r in rows if lo < r["tokens"] <= hi]
        if not group:
            continue
        names = ", ".join(sorted((r["name"].removeprefix("example")
                                  for r in group), key=int))
        word = "example" if len(group) == 1 else "examples"
        median = statistics.median(t for r in group for t in r["model"])
        top = max(max(r["model"]) for r in group)
        ax.annotate(f"{word} {names}\n~{median:.0f} s", ((lo + hi) / 2, top),
                    xytext=(0, 8), textcoords="offset points",
                    ha="center", va="bottom", fontsize=8, color=INK)
    ax.set_xlim(0, 800)
    ax.set_ylim(0, max(max(r["model"]) for r in rows) * 1.15)
    ax.set_xlabel("Input tokens")
    ax.set_ylabel("Model inference time (s)")
    ax.set_title("Stage 2 (one L40S): inference time steps up at each "
                 "padding size", loc="left", color=INK)
    style(ax)
    fig.tight_layout()
    fig.savefig(OUT / "stage2_tokens.png", dpi=200)
    plt.close(fig)


def plot_confidence(rows):
    rows = sorted(rows, key=lambda r: r["score"])
    fig, ax = plt.subplots(figsize=(8, 5.5))
    # Bands from the upstream output documentation, in neutral grays so they
    # read as background, labelled in text.
    for lo, hi, shade, label in ((0, 0.6, "#ecebe7", "likely failed"),
                                 (0.6, 0.8, "#f5f4f1", "grey zone"),
                                 (0.8, 1.0, "#fcfcfb", "confident")):
        ax.axvspan(lo, hi, color=shade, zorder=0)
        ax.text((lo + hi) / 2, 1.0, label, transform=ax.get_xaxis_transform(),
                ha="center", va="bottom", fontsize=9, color=MUTED)
    for y, r in enumerate(rows):
        ax.plot([0, r["score"]], [y, y], color=GRID, lw=2, zorder=1)
        ax.plot(r["score"], y, "o", ms=8, color=SERIES, mec="white", mew=1,
                zorder=2)
        ax.annotate(f"{r['score']:.2f} {r['metric']}", (r["score"], y),
                    xytext=(8, 0), textcoords="offset points", va="center",
                    fontsize=8, color=INK)
    ax.set_xlim(0, 1.08)
    ax.set_yticks(range(len(rows)), [r["name"] for r in rows])
    ax.set_xlabel("ipTM (pTM for single-chain inputs), top-ranked prediction")
    ax.set_title("Prediction confidence per example", loc="left", color=INK,
                 pad=18)
    style(ax)
    ax.grid(False)
    fig.tight_layout()
    fig.savefig(OUT / "confidence.png", dpi=200)
    plt.close(fig)


def main():
    rows = load()
    if not rows:
        raise SystemExit("no results found in example*/output/")
    OUT.mkdir(exist_ok=True)
    plot_stage1(rows)
    plot_stage2(rows)
    plot_confidence(rows)
    for p in sorted(OUT.glob("*.png")):
        print(p.relative_to(HERE))


if __name__ == "__main__":
    main()
