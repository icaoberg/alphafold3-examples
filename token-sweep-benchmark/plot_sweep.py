#!/usr/bin/env python3
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only

"""Plot the token-size sweep from sweep_summary.csv.

Usage, from this directory (after ./collect_sweep.py):
  ./plot_sweep.py

Writes:
  plots/sweep_runtime.png  warm inference time vs tokens per GPU, with
                           DeepMind's A100/H100 timings and OOM points
  plots/sweep_compile.png  cold vs warm time, i.e. compilation overhead
  plots/sweep_memory.png   real peak GPU memory vs tokens (once runs
                           have recorded peak_gpu_mem_mib)
"""

import csv
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = HERE / "plots"

GPU_ORDER = ["v100-32", "l40s-48", "h100-80"]
LABEL = {"v100-32": "V100 32GB", "l40s-48": "L40S 48GB",
         "h100-80": "H100 80GB"}
COLOR = {"v100-32": "tab:green", "l40s-48": "tab:blue",
         "h100-80": "tab:red"}


def num(x):
    return float(x) if x not in ("", None) else None


def load():
    by_gpu = defaultdict(list)
    with open(HERE / "sweep_summary.csv") as f:
        for r in csv.DictReader(f):
            r["tokens"] = int(r["tokens"])
            by_gpu[r["gpu"]].append(r)
    order = [g for g in GPU_ORDER if g in by_gpu]
    order += sorted(g for g in by_gpu if g not in GPU_ORDER)
    return {g: sorted(by_gpu[g], key=lambda r: r["tokens"]) for g in order}


def official(rows_by_gpu):
    pts = {}
    for rows in rows_by_gpu.values():
        for r in rows:
            for key, name in (("a100_official_seconds", "A100 80GB"),
                              ("h100_official_seconds", "H100 80GB")):
                if num(r[key]) is not None:
                    pts.setdefault(name, {})[r["tokens"]] = num(r[key])
    return pts


def plot_runtime(data):
    fig, ax = plt.subplots(figsize=(7, 4.5))
    ymax = 1.0
    for gpu, rows in data.items():
        ok = [(r["tokens"], num(r["warm_seconds"])) for r in rows
              if r["status"] == "ok" and num(r["warm_seconds"])]
        if ok:
            x, y = zip(*ok)
            ymax = max(ymax, *y)
            ax.plot(x, y, "o-", color=COLOR.get(gpu), label=LABEL.get(gpu, gpu))
    for name, pts in official(data).items():
        x, y = zip(*sorted(pts.items()))
        ymax = max(ymax, *y)
        ax.plot(x, y, "s--", color="gray", alpha=0.6 if "A100" in name else 1,
                mfc="none", label=f"{name} (DeepMind)")
    # OOM points along the top of the plot.
    for gpu, rows in data.items():
        oom = [r["tokens"] for r in rows if r["status"] == "oom"]
        if oom:
            ax.plot(oom, [ymax * 2] * len(oom), "x", color=COLOR.get(gpu),
                    ms=9, mew=2)
    ax.text(0.01, 0.97, "x = out of memory", transform=ax.transAxes,
            va="top", fontsize=8, color="dimgray")
    ax.set_yscale("log")
    ax.set_xlabel("Input size (tokens)")
    ax.set_ylabel("Warm inference time per seed (s)")
    ax.set_title("AlphaFold 3 inference time vs input size")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend(fontsize=8, loc="lower right")
    fig.tight_layout()
    fig.savefig(OUT / "sweep_runtime.png", dpi=200)
    plt.close(fig)


def plot_compile(data):
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for gpu, rows in data.items():
        ok = [(r["tokens"], num(r["cold_seconds"]), num(r["warm_seconds"]))
              for r in rows if r["status"] == "ok" and num(r["cold_seconds"])
              and num(r["warm_seconds"])]
        if ok:
            x, cold, warm = zip(*ok)
            c = COLOR.get(gpu)
            ax.plot(x, cold, "o-", color=c,
                    label=f"{LABEL.get(gpu, gpu)} cold (with compile)")
            ax.plot(x, warm, "o:", color=c, mfc="none",
                    label=f"{LABEL.get(gpu, gpu)} warm")
    ax.set_yscale("log")
    ax.set_xlabel("Input size (tokens)")
    ax.set_ylabel("Inference time (s)")
    ax.set_title("JAX compilation overhead: first vs second seed")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(OUT / "sweep_compile.png", dpi=200)
    plt.close(fig)


def plot_memory(data):
    have = any(num(r["peak_gpu_mem_mib"]) for rows in data.values()
               for r in rows)
    if not have:
        print("No runs with peak_gpu_mem_mib recorded yet; "
              "skipping sweep_memory.png")
        return
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for gpu, rows in data.items():
        pts = [(r["tokens"], num(r["peak_gpu_mem_mib"]) / 1024) for r in rows
               if num(r["peak_gpu_mem_mib"])]
        c = COLOR.get(gpu)
        if pts:
            x, y = zip(*pts)
            ax.plot(x, y, "o-", color=c, label=LABEL.get(gpu, gpu))
        total = next((num(r["gpu_mem_total_mib"]) for r in rows
                      if num(r["gpu_mem_total_mib"])), None)
        if total:
            ax.axhline(total / 1024, color=c, ls="--", alpha=0.5)
    ax.set_xlabel("Input size (tokens)")
    ax.set_ylabel("Peak GPU memory (GiB)")
    ax.set_title("Real peak GPU memory (dashed = card capacity)")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(OUT / "sweep_memory.png", dpi=200)
    plt.close(fig)


def main():
    OUT.mkdir(exist_ok=True)
    data = load()
    plot_runtime(data)
    plot_compile(data)
    plot_memory(data)
    print(f"Wrote plots to {OUT}/")


if __name__ == "__main__":
    main()
