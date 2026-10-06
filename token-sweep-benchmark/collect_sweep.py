#!/usr/bin/env python3
#
# Copyright (C) 2026 Ivan Cao-Berg and River Zhu
# SPDX-License-Identifier: GPL-2.0-only

"""Collect the token-size sweep into sweep_results.csv and sweep_summary.csv.

Usage, from this directory:
  ./collect_sweep.py

Reads every logs/af3-sweep-*.out written by sweep.sh.

- sweep_results.csv: one row per run.
- sweep_summary.csv: one row per GPU and size, medians over successful runs.

GPU memory comes from JAX's peak_bytes_in_use, printed by sweep.sh's wrapper:
the real peak inside XLA's preallocated pool. The nvidia-smi peak is kept as
smi_peak_mib, but in normal runs it only shows the 95% preallocation.

Seed 1 includes JAX compilation (cold); seed 2 is compile-free (warm), the one
to compare with DeepMind's published timings.
"""

import csv
import re
import statistics
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent

# DeepMind docs/performance.md, compile-free seconds on one GPU.
OFFICIAL = {
    1024: {"a100-80": 62, "h100-80": 34},
    2048: {"a100-80": 275, "h100-80": 144},
    3072: {"a100-80": 703, "h100-80": 367},
    4096: {"a100-80": 1434, "h100-80": 774},
    5120: {"a100-80": 2547, "h100-80": 1416},
}

RUN_FIELDS = [
    "tokens", "gpu", "repeat", "memprofile", "status", "cold_seconds",
    "warm_seconds", "compile_seconds", "featurisation_seconds",
    "peak_gpu_mem_mib", "jax_limit_mib", "smi_peak_mib", "gpu_mem_total_mib",
    "elapsed_seconds", "attention",
    "gpu_name", "node", "job_id", "log",
]

SUMMARY_FIELDS = [
    "gpu", "tokens", "status", "n_ok", "n_oom", "n_other",
    "cold_seconds", "warm_seconds", "compile_seconds", "peak_gpu_mem_mib",
    "gpu_mem_total_mib", "a100_official_seconds", "h100_official_seconds",
]

HEADER = re.compile(r"^Benchmark (tokens|gpu|gpu name|gpu memory|repeat|"
                    r"attention|memprofile|node|job id): (.*)$")
INFERENCE = re.compile(r"Running model inference with seed (\d+) took "
                       r"([\d.]+) seconds")
FEATURISATION = re.compile(r"Featurising data with \d+ seed\(s\) took "
                           r"([\d.]+) seconds")
JAX_PEAK = re.compile(r"^JAX peak bytes in use: (\d+)")
JAX_LIMIT = re.compile(r"^JAX bytes limit: (\d+)")
# "Peak GPU memory MiB" is the label used by the first version of sweep.sh.
SMI_PEAK = re.compile(r"^(?:nvidia-smi peak|Peak GPU memory) MiB: (\d+)")
MIB = 2 ** 20
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
        elif m := FEATURISATION.search(line):
            row["featurisation_seconds"] = m.group(1)
        elif m := JAX_PEAK.match(line):
            row["peak_gpu_mem_mib"] = f"{int(m.group(1)) / MIB:.0f}"
        elif m := JAX_LIMIT.match(line):
            row["jax_limit_mib"] = f"{int(m.group(1)) / MIB:.0f}"
        elif m := SMI_PEAK.match(line):
            row["smi_peak_mib"] = m.group(1)
        elif m := ELAPSED.match(line):
            row["elapsed_seconds"] = m.group(1)  # keep the last one
        elif line.startswith("Done running"):
            done = True
        elif "RESOURCE_EXHAUSTED" in line or "out of memory" in line.lower():
            oom = True
        elif "DUE TO TIME LIMIT" in line:
            timeout = True

    if done:
        row["status"] = "ok"
    elif oom:
        row["status"] = "oom"
    elif timeout:
        row["status"] = "timeout"
    elif "elapsed_seconds" not in row:
        row["status"] = "incomplete"
    else:
        row["status"] = "failed"

    cold, warm = seeds.get(1), seeds.get(2)
    row["cold_seconds"] = f"{cold:.1f}" if cold is not None else ""
    row["warm_seconds"] = f"{warm:.1f}" if warm is not None else ""
    row["compile_seconds"] = (f"{cold - warm:.1f}"
                              if cold is not None and warm is not None else "")
    if m := re.match(r"(\d+)", row.pop("gpu_memory", "")):
        row["gpu_mem_total_mib"] = m.group(1)
    return row


def median(values):
    values = [float(v) for v in values if v not in ("", None)]
    return f"{statistics.median(values):.1f}" if values else ""


def summarise(rows):
    groups = defaultdict(list)
    for r in rows:
        groups[r.get("gpu", ""), int(r.get("tokens") or 0)].append(r)

    summary = []
    for (gpu, n), runs in sorted(groups.items()):
        timing = [r for r in runs if r.get("memprofile") != "1"]
        ok = [r for r in timing if r["status"] == "ok"]
        n_oom = sum(r["status"] == "oom" for r in runs)
        n_other = sum(r["status"] not in ("ok", "oom") for r in timing)
        if ok:
            status = "ok"
        elif n_oom:
            status = "oom"
        else:
            status = timing[0]["status"] if timing else "mem-only"
        # Real peak memory: JAX's number from any successful run.
        mem_ok = [r for r in runs if r["status"] == "ok"]
        official = OFFICIAL.get(n, {})
        summary.append({
            "gpu": gpu, "tokens": n, "status": status, "n_ok": len(ok),
            "n_oom": n_oom, "n_other": n_other,
            "cold_seconds": median(r["cold_seconds"] for r in ok),
            "warm_seconds": median(r["warm_seconds"] for r in ok),
            "compile_seconds": median(r["compile_seconds"] for r in ok),
            "peak_gpu_mem_mib": median(r.get("peak_gpu_mem_mib")
                                       for r in mem_ok),
            "gpu_mem_total_mib": next((r["gpu_mem_total_mib"] for r in runs
                                       if r.get("gpu_mem_total_mib")), ""),
            "a100_official_seconds": official.get("a100-80", ""),
            "h100_official_seconds": official.get("h100-80", ""),
        })
    return summary


def write_csv(path, fields, rows):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)


def main():
    logs = sorted((HERE / "logs").glob("af3-sweep-*.out"))
    rows = [parse(f) for f in logs]
    rows.sort(key=lambda r: (r.get("gpu", ""), int(r.get("tokens") or 0),
                             r.get("memprofile", ""),
                             int(r.get("repeat") or 0)))
    write_csv(HERE / "sweep_results.csv", RUN_FIELDS, rows)
    summary = summarise(rows)
    write_csv(HERE / "sweep_summary.csv", SUMMARY_FIELDS, summary)
    print(f"Wrote {len(rows)} runs to sweep_results.csv and "
          f"{len(summary)} rows to sweep_summary.csv\n")

    cols = ["gpu", "tokens", "status", "n_ok", "cold_seconds", "warm_seconds",
            "compile_seconds", "peak_gpu_mem_mib", "a100_official_seconds",
            "h100_official_seconds"]
    heads = ["gpu", "tokens", "status", "n", "cold", "warm", "compile",
             "peakMiB", "A100", "H100"]
    widths = [9, 7, 10, 3, 8, 8, 8, 8, 6, 6]
    print(" ".join(f"{h:>{w}}" for h, w in zip(heads, widths)))
    last_gpu = None
    for s in summary:
        if last_gpu is not None and s["gpu"] != last_gpu:
            print()
        last_gpu = s["gpu"]
        print(" ".join(f"{str(s[c]):>{w}}" for c, w in zip(cols, widths)))

    bad = [r for r in rows if r["status"] not in ("ok", "oom")]
    if bad:
        print(f"\n{len(bad)} run(s) neither ok nor oom:")
        for r in bad:
            print(f"  {r['status']:<10} {r['log']}")


if __name__ == "__main__":
    main()
