#!/usr/bin/env python3
"""Run the complete currently-executable HAMSA evaluation matrix.

The runner intentionally separates executable full-core configurations from
frontend-only/native-interface studies:

  B0: original CV32E40P + evaluation-only counters
  H0: HAMSA integration, Issue2 disabled
  H1: HAMSA integration, Issue2 enabled, sequential 32-bit pair assembly
  H2-32: reserved for full-core L0 integration; rejected until the generated
         core actually consumes the 128-bit frontend. Do not silently alias H1.

For paper-quality data the same firmware image is used for all full-core modes.
"""
from __future__ import annotations

import argparse
import csv
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "evaluation" / "run_example_vsim.py"
PARSE = ROOT / "evaluation" / "parse_hamsa_log.py"
METRICS = ROOT / "evaluation" / "compute_metrics.py"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("firmware", type=Path)
    ap.add_argument("--name", default="firmware")
    ap.add_argument("--configs", default="B0,H0,H1")
    ap.add_argument("--maxcycles", type=int, default=20_000_000)
    ap.add_argument("--out", type=Path, default=ROOT / "evaluation/results/full_matrix.csv")
    args = ap.parse_args()

    fw = args.firmware.resolve()
    if not fw.exists():
        raise SystemExit(f"firmware not found: {fw}")

    configs = [x.strip() for x in args.configs.split(",") if x.strip()]
    allowed = {"B0", "H0", "H1"}
    bad = set(configs) - allowed
    if bad:
        raise SystemExit(
            "full-core runner currently accepts B0,H0,H1 only. "
            f"Unsupported: {', '.join(sorted(bad))}. H2 is intentionally not "
            "aliased to H1; finish real L0/full-core integration first."
        )

    logdir = ROOT / "evaluation/results/logs"
    logdir.mkdir(parents=True, exist_ok=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    rows = []
    for cfg in configs:
        log = logdir / f"{args.name}__{cfg}.log"
        print(f"[HAMSA] running {cfg}: {fw}")
        proc = subprocess.run(
            ["python3", str(RUN), cfg, str(fw), "--maxcycles", str(args.maxcycles)],
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
        tokens = {}
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
        "block_busy", "block_decode", "l0_lookups", "l0_hits",
    ]
    with args.out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, "") for k in fields})
    print(f"[HAMSA] wrote {args.out}")

    # Keep post-processing optional: older compute_metrics revisions may expect
    # additional metadata columns. The raw matrix is always preserved.
    if METRICS.exists():
        print(f"[HAMSA] raw results ready for {METRICS.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
