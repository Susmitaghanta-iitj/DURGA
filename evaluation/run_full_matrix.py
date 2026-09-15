#!/usr/bin/env python3
"""Run the complete executable HAMSA evaluation matrix.

B0      original CV32E40P
H0      HAMSA integration, Issue2 disabled
H1      HAMSA Issue2 enabled with sequential 32-bit pair assembly
H2-32   real 128-bit L0/RV32C frontend with four 32-bit refill beats
H2-128  same frontend with one native 128-bit line transaction

The same firmware image and simulator options are used for every selected row.
"""
from __future__ import annotations

import argparse
import csv
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "evaluation" / "run_example_vsim.py"
METRICS = ROOT / "evaluation" / "compute_metrics.py"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("firmware", type=Path)
    ap.add_argument("--name", default="firmware")
    ap.add_argument("--configs", default="B0,H0,H1,H2-32,H2-128")
    ap.add_argument("--maxcycles", type=int, default=20_000_000)
    ap.add_argument("--out", type=Path,
                    default=ROOT / "evaluation/results/full_matrix.csv")
    args = ap.parse_args()

    fw = args.firmware.resolve()
    if not fw.exists():
        raise SystemExit(f"firmware not found: {fw}")

    configs = [x.strip() for x in args.configs.split(",") if x.strip()]
    allowed = {"B0", "H0", "H1", "H2-32", "H2-128"}
    bad = set(configs) - allowed
    if bad:
        raise SystemExit(f"unsupported configurations: {', '.join(sorted(bad))}")

    logdir = ROOT / "evaluation/results/logs"
    logdir.mkdir(parents=True, exist_ok=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    rows = []
    for cfg in configs:
        log = logdir / f"{args.name}__{cfg}.log"
        print(f"[HAMSA] running {cfg}: {fw}")
        proc = subprocess.run(
            ["python3", str(RUN), cfg, str(fw),
             "--maxcycles", str(args.maxcycles)],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        text = proc.stdout + ("\n" if proc.stdout and proc.stderr else "") + proc.stderr
        log.write_text(text)
        print(text, end="")
        if proc.returncode:
            raise SystemExit(f"{cfg} failed; see {log}")

        metric_lines = [ln for ln in text.splitlines() if "HAMSA_METRIC" in ln]
        if not metric_lines:
            raise SystemExit(f"{cfg} emitted no HAMSA_METRIC line; see {log}")

        tokens: dict[str, str] = {}
        for tok in metric_lines[-1].split():
            if "=" in tok:
                k, v = tok.split("=", 1)
                tokens[k] = v.rstrip(",")
        tokens["benchmark"] = args.name
        tokens["configuration"] = cfg
        rows.append(tokens)

    fields = [
        "benchmark", "configuration", "cycles", "issue1_retired",
        "issue2_issued", "issue2_retired", "issue2_blocked", "issue2_killed",
        "block_raw", "block_waw", "block_unsupported", "block_serializing",
        "block_busy", "block_decode", "l0_lookups", "l0_hits", "l0_refills",
    ]
    with args.out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, "0") for k in fields})

    print(f"[HAMSA] wrote {args.out}")
    if METRICS.exists():
        print(f"[HAMSA] derive metrics with: python3 {METRICS.relative_to(ROOT)} {args.out}")


if __name__ == "__main__":
    main()
