#!/usr/bin/env python3
"""Run B0/H0/H1/H2 benchmark commands and collect HAMSA metrics.

This script does not assume a particular simulator. Supply a shell command
containing {benchmark} and {configuration}; the command must emit HAMSA_METRIC
key=value tokens to stdout/stderr.

Example:
  python3 evaluation/run_benchmark_matrix.py \
    --benchmarks coremark,aha-mont64 \
    --configs B0,H1,H2 \
    --command './run_sim.sh {configuration} {benchmark}' \
    --out evaluation/results/raw.csv
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import shlex
import subprocess
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


def git_sha() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    except Exception:
        return ""


def parse_metrics(text: str) -> dict[str, str]:
    metrics: dict[str, str] = {}
    for line in text.splitlines():
        if "HAMSA_METRIC" not in line:
            continue
        for key, value in METRIC_RE.findall(line):
            metrics[key] = value
    return metrics


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--benchmarks", required=True, help="comma-separated names")
    p.add_argument("--configs", default="B0,H0,H1,H2")
    p.add_argument("--command", required=True, help="shell command template")
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--logs", type=Path, default=Path("evaluation/results/logs"))
    p.add_argument("--tool", default=os.getenv("HAMSA_TOOL", ""))
    p.add_argument("--tool-version", default=os.getenv("HAMSA_TOOL_VERSION", ""))
    p.add_argument("--compiler", default=os.getenv("HAMSA_COMPILER", ""))
    p.add_argument("--compiler-version", default=os.getenv("HAMSA_COMPILER_VERSION", ""))
    p.add_argument("--compiler-flags", default=os.getenv("HAMSA_COMPILER_FLAGS", ""))
    p.add_argument("--clock-mhz", default=os.getenv("HAMSA_CLOCK_MHZ", ""))
    p.add_argument("--memory-config", default=os.getenv("HAMSA_MEMORY_CONFIG", ""))
    args = p.parse_args()

    benchmarks = [x.strip() for x in args.benchmarks.split(",") if x.strip()]
    configs = [x.strip() for x in args.configs.split(",") if x.strip()]
    invalid = set(configs) - {"B0", "H0", "H1", "H2"}
    if invalid:
        raise SystemExit(f"invalid configuration(s): {', '.join(sorted(invalid))}")

    args.logs.mkdir(parents=True, exist_ok=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, str]] = []
    sha = git_sha()

    for benchmark in benchmarks:
        for configuration in configs:
            command = args.command.format(benchmark=benchmark, configuration=configuration)
            print(f"[HAMSA] {configuration}/{benchmark}: {command}")
            proc = subprocess.run(command, shell=True, text=True, capture_output=True)
            combined = proc.stdout + ("\n" if proc.stdout and proc.stderr else "") + proc.stderr
            log_path = args.logs / f"{benchmark}__{configuration}.log"
            log_path.write_text(combined)
            if proc.returncode != 0:
                raise SystemExit(f"command failed ({proc.returncode}); see {log_path}")

            metrics = parse_metrics(combined)
            if "cycles" not in metrics:
                raise SystemExit(f"no HAMSA_METRIC cycles=... in {log_path}")

            row = {field: "" for field in FIELDS}
            row.update(metrics)
            row.update({
                "benchmark": benchmark,
                "configuration": configuration,
                "git_sha": sha,
                "tool": args.tool,
                "tool_version": args.tool_version,
                "compiler": args.compiler,
                "compiler_version": args.compiler_version,
                "compiler_flags": args.compiler_flags,
                "clock_mhz": args.clock_mhz,
                "memory_config": args.memory_config,
            })
            rows.append(row)

    with args.out.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"[HAMSA] wrote {len(rows)} rows to {args.out}")


if __name__ == "__main__":
    main()
