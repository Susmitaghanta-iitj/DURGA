#!/usr/bin/env python3
"""Parse key=value SPARV simulation counters and emit one CSV row.

Expected log lines may contain tokens such as:
  cycles=100 retired=130 l0_lookups=40 l0_hits=31 ...
Unknown tokens are ignored. Missing counters default to zero.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

COUNTERS = [
    "cycles", "retired", "dual_pairs", "l0_lookups", "l0_hits",
    "demand_misses", "prefetch_candidates", "prefetch_issued",
    "prefetch_fills", "prefetch_useful", "prefetch_wasted",
    "prefetch_suppressed", "tcim_requests", "mac8_ops", "mac16_ops",
    "mac32_ops", "sparv_stall_cycles",
]

TOKEN = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)=(0x[0-9a-fA-F]+|[-+]?[0-9]+(?:\.[0-9]+)?)")


def div(a: float, b: float) -> float:
    return a / b if b else 0.0


def parse_log(path: Path) -> dict[str, float]:
    values: dict[str, float] = {name: 0.0 for name in COUNTERS}
    for line in path.read_text(errors="replace").splitlines():
        for key, raw in TOKEN.findall(line):
            if key not in values:
                continue
            values[key] = float(int(raw, 16)) if raw.lower().startswith("0x") else float(raw)
    return values


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("log", type=Path)
    p.add_argument("--configuration", required=True)
    p.add_argument("--benchmark", required=True)
    p.add_argument("--refill-mode", default="32x4")
    p.add_argument("--frequency-mhz", type=float, default=0.0)
    p.add_argument("--area-um2", type=float, default=0.0)
    p.add_argument("--power-mw", type=float, default=0.0)
    p.add_argument("--energy-uj", type=float, default=0.0)
    p.add_argument("--notes", default="")
    p.add_argument("--output", type=Path)
    args = p.parse_args()

    v = parse_log(args.log)
    cycles = v["cycles"]
    retired = v["retired"]
    lookups = v["l0_lookups"]
    hits = v["l0_hits"]
    fills = v["prefetch_fills"]
    useful = v["prefetch_useful"]
    misses = v["demand_misses"]

    row = {
        "configuration": args.configuration,
        "benchmark": args.benchmark,
        "refill_mode": args.refill_mode,
        "cycles": int(cycles),
        "retired": int(retired),
        "ipc": div(retired, cycles),
        "dual_pairs": int(v["dual_pairs"]),
        "dual_issue_util": div(v["dual_pairs"], cycles),
        "l0_lookups": int(lookups),
        "l0_hits": int(hits),
        "l0_hit_rate": div(hits, lookups),
        "demand_misses": int(misses),
        "prefetch_candidates": int(v["prefetch_candidates"]),
        "prefetch_issued": int(v["prefetch_issued"]),
        "prefetch_fills": int(fills),
        "prefetch_useful": int(useful),
        "prefetch_wasted": int(v["prefetch_wasted"]),
        "prefetch_suppressed": int(v["prefetch_suppressed"]),
        "prefetch_accuracy": div(useful, fills),
        "prefetch_coverage": div(useful, misses + useful),
        "tcim_requests": int(v["tcim_requests"]),
        "mac8_ops": int(v["mac8_ops"]),
        "mac16_ops": int(v["mac16_ops"]),
        "mac32_ops": int(v["mac32_ops"]),
        "sparv_stall_cycles": int(v["sparv_stall_cycles"]),
        "frequency_mhz": args.frequency_mhz,
        "area_um2": args.area_um2,
        "power_mw": args.power_mw,
        "energy_uj": args.energy_uj,
        "notes": args.notes,
    }

    fields = list(row)
    if args.output:
        exists = args.output.exists() and args.output.stat().st_size > 0
        with args.output.open("a", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=fields)
            if not exists:
                writer.writeheader()
            writer.writerow(row)
    else:
        writer = csv.DictWriter(__import__("sys").stdout, fieldnames=fields)
        writer.writeheader()
        writer.writerow(row)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
