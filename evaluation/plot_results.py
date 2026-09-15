#!/usr/bin/env python3
"""Create simple paper-ready HAMSA plots from a metrics CSV.

No styling library is required; matplotlib defaults are used deliberately so
results remain easy to reproduce and restyle later.
"""
from __future__ import annotations
import argparse
import csv
from collections import defaultdict
from pathlib import Path


def f(row, key, default=0.0):
    try:
        return float(row.get(key, "") or default)
    except ValueError:
        return default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", type=Path)
    ap.add_argument("--outdir", type=Path, default=Path("evaluation/results/plots"))
    args = ap.parse_args()
    import matplotlib.pyplot as plt

    rows = list(csv.DictReader(args.csv.open()))
    args.outdir.mkdir(parents=True, exist_ok=True)
    bybench = defaultdict(dict)
    for r in rows:
        bybench[r["benchmark"]][r["configuration"]] = r

    benches = sorted(bybench)
    configs = [c for c in ["B0", "H0", "H1", "H2-32", "H2-128"]
               if any(c in bybench[b] for b in benches)]

    # Speedup relative to B0.
    for cfg in configs:
        if cfg == "B0":
            continue
        xs, ys = [], []
        for b in benches:
            if "B0" in bybench[b] and cfg in bybench[b]:
                base = f(bybench[b]["B0"], "cycles")
                cur = f(bybench[b][cfg], "cycles")
                if base and cur:
                    xs.append(b); ys.append(base / cur)
        if xs:
            plt.figure(figsize=(max(6, len(xs)*0.8), 4))
            plt.bar(xs, ys)
            plt.axhline(1.0, linewidth=1)
            plt.ylabel("Speedup vs B0")
            plt.title(cfg)
            plt.xticks(rotation=35, ha="right")
            plt.tight_layout()
            plt.savefig(args.outdir / f"speedup_{cfg}.png", dpi=180)
            plt.close()

    # IPC by configuration.
    labels, vals = [], []
    for b in benches:
        for cfg in configs:
            if cfg not in bybench[b]:
                continue
            r = bybench[b][cfg]
            cyc = f(r, "cycles")
            retired = f(r, "issue1_retired") + f(r, "issue2_retired")
            if cyc:
                labels.append(f"{b}\n{cfg}")
                vals.append(retired / cyc)
    if labels:
        plt.figure(figsize=(max(7, len(labels)*0.6), 4))
        plt.bar(labels, vals)
        plt.ylabel("IPC")
        plt.xticks(rotation=45, ha="right")
        plt.tight_layout()
        plt.savefig(args.outdir / "ipc.png", dpi=180)
        plt.close()

    # Issue2 utilization for dual-issue configurations.
    labels, vals = [], []
    for b in benches:
        for cfg, r in bybench[b].items():
            i1 = f(r, "issue1_retired"); i2 = f(r, "issue2_retired")
            if i2 or f(r, "issue2_issued"):
                total = i1 + i2
                labels.append(f"{b}\n{cfg}")
                vals.append((i2 / total) if total else 0.0)
    if labels:
        plt.figure(figsize=(max(7, len(labels)*0.6), 4))
        plt.bar(labels, vals)
        plt.ylabel("Issue2 retired / total retired")
        plt.xticks(rotation=45, ha="right")
        plt.tight_layout()
        plt.savefig(args.outdir / "issue2_utilization.png", dpi=180)
        plt.close()

    print(f"wrote plots to {args.outdir}")

if __name__ == "__main__":
    main()
