#!/usr/bin/env python3
"""Parse HAMSA_METRIC lines from simulator logs into one CSV row.

Expected log tokens may appear one per line or several per line, for example:
  HAMSA_METRIC cycles=12345 issue1_retired=10000 issue2_retired=2100
  HAMSA_METRIC issue2_issued=2200 issue2_blocked=1400 issue2_killed=12

The parser is intentionally simulator-agnostic. A testbench only needs to print
key=value pairs prefixed by HAMSA_METRIC.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

METRIC_RE = re.compile(r"([A-Za-z0-9_]+)=([^\s,]+)")

FIELDS = [
    "benchmark", "configuration", "git_sha", "tool", "tool_version",
    "compiler", "compiler_version", "compiler_flags", "clock_mhz",
    "memory_config", "cycles", "issue1_retired", "issue2_issued",
    "issue2_retired", "issue2_blocked", "issue2_killed", "block_raw",
    "block_waw", "block_unsupported", "block_serializing", "block_busy",
    "block_decode", "l0_lookups", "l0_hits", "benchmark_score",
    "area_um2", "cell_area_um2", "fmax_mhz", "dynamic_power_mw",
    "leakage_power_mw", "avg_power_mw", "notes",
]


def parse_log(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(errors="replace").splitlines():
        if "HAMSA_METRIC" not in line:
            continue
        for key, value in METRIC_RE.findall(line):
            result[key] = value
    return result


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("log", type=Path)
    p.add_argument("--benchmark", required=True)
    p.add_argument("--configuration", required=True, choices=["B0", "H0", "H1", "H2"])
    p.add_argument("--git-sha", default="")
    p.add_argument("--tool", default="")
    p.add_argument("--tool-version", default="")
    p.add_argument("--compiler", default="")
    p.add_argument("--compiler-version", default="")
    p.add_argument("--compiler-flags", default="")
    p.add_argument("--clock-mhz", default="")
    p.add_argument("--memory-config", default="")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--append", action="store_true")
    args = p.parse_args()

    row = {field: "" for field in FIELDS}
    row.update(parse_log(args.log))
    row.update({
        "benchmark": args.benchmark,
        "configuration": args.configuration,
        "git_sha": args.git_sha,
        "tool": args.tool,
        "tool_version": args.tool_version,
        "compiler": args.compiler,
        "compiler_version": args.compiler_version,
        "compiler_flags": args.compiler_flags,
        "clock_mhz": args.clock_mhz,
        "memory_config": args.memory_config,
    })

    required = ["cycles"]
    missing = [key for key in required if not row.get(key)]
    if missing:
        raise SystemExit(f"missing required metric(s) in {args.log}: {', '.join(missing)}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    mode = "a" if args.append and args.output.exists() else "w"
    with args.output.open(mode, newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        if mode == "w":
            writer.writeheader()
        writer.writerow(row)


if __name__ == "__main__":
    main()
