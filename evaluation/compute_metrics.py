#!/usr/bin/env python3
"""Compute derived HAMSA-DI evaluation metrics from the raw-results CSV."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def f(row, key):
    value = row.get(key, "").strip()
    return float(value) if value else None


def safe_div(a, b):
    if a is None or b in (None, 0):
        return None
    return a / b


def fmt(x):
    return "" if x is None else f"{x:.6f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv_file", type=Path)
    ap.add_argument("--baseline", default="B0")
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()

    with args.csv_file.open(newline="") as fh:
        rows = list(csv.DictReader(fh))

    baseline_cycles = {}
    for row in rows:
        if row.get("configuration") == args.baseline:
            cyc = f(row, "cycles")
            if cyc is not None:
                baseline_cycles[row.get("benchmark", "")] = cyc

    fields = list(rows[0].keys()) if rows else []
    derived = [
        "total_retired",
        "ipc",
        "issue2_issue_rate",
        "issue2_retirement_rate",
        "pair_utilization",
        "issue2_block_rate",
        "issue2_kill_rate",
        "l0_hit_rate",
        "speedup_vs_baseline",
        "cycle_reduction_pct",
        "energy_mj",
    ]

    out_rows = []
    for row in rows:
        cycles = f(row, "cycles")
        i1 = f(row, "issue1_retired")
        i2_issue = f(row, "issue2_issued")
        i2_ret = f(row, "issue2_retired")
        i2_blk = f(row, "issue2_blocked")
        i2_kill = f(row, "issue2_killed")
        lookups = f(row, "l0_lookups")
        hits = f(row, "l0_hits")
        power_mw = f(row, "avg_power_mw")
        clock_mhz = f(row, "clock_mhz")

        total = (i1 + i2_ret) if i1 is not None and i2_ret is not None else None
        base = baseline_cycles.get(row.get("benchmark", ""))
        speedup = safe_div(base, cycles)
        reduction = None
        if base not in (None, 0) and cycles is not None:
            reduction = 100.0 * (base - cycles) / base

        energy_mj = None
        if power_mw is not None and cycles is not None and clock_mhz not in (None, 0):
            # time_s = cycles / (clock_mhz * 1e6); mW*s = mJ
            energy_mj = power_mw * cycles / (clock_mhz * 1e6)

        row.update({
            "total_retired": fmt(total),
            "ipc": fmt(safe_div(total, cycles)),
            "issue2_issue_rate": fmt(safe_div(i2_issue, cycles)),
            "issue2_retirement_rate": fmt(safe_div(i2_ret, cycles)),
            "pair_utilization": fmt(safe_div(i2_ret, total)),
            "issue2_block_rate": fmt(safe_div(i2_blk, (i2_issue + i2_blk) if i2_issue is not None and i2_blk is not None else None)),
            "issue2_kill_rate": fmt(safe_div(i2_kill, i2_issue)),
            "l0_hit_rate": fmt(safe_div(hits, lookups)),
            "speedup_vs_baseline": fmt(speedup),
            "cycle_reduction_pct": fmt(reduction),
            "energy_mj": fmt(energy_mj),
        })
        out_rows.append(row)

    out = args.output or args.csv_file.with_name(args.csv_file.stem + "_derived.csv")
    with out.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields + derived)
        writer.writeheader()
        writer.writerows(out_rows)

    print(out)


if __name__ == "__main__":
    main()
