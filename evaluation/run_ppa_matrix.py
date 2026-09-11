#!/usr/bin/env python3
"""Generate RTL variants and drive an identical external PPA flow for each one.

The script intentionally does not hard-code a technology or FPGA vendor. Give it
one synthesis/P&R command template that consumes {manifest}, {top}, {config},
{outdir}, and optional {params}; the exact same template is invoked for every
configuration. The backend may write ppa.json in each outdir with any of:
area, cells, lut, ff, bram, dsp, fmax_mhz, avg_power_mw, leakage_mw.

Example:
  python3 evaluation/run_ppa_matrix.py \
    --command 'my_flow --manifest {manifest} --top {top} --out {outdir} {params}'
"""
from __future__ import annotations

import argparse
import csv
import json
import shlex
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def prepare(config: str) -> tuple[str, str, str]:
    """Return (manifest, top, parameter options) after generating needed RTL."""
    if config == "B0":
        return "cv32e40p_manifest.flist", "cv32e40p_core", ""
    if config in {"H0", "H1"}:
        subprocess.run(["python3", "util/gen_hamsa_core.py"], cwd=ROOT, check=True)
        # gen_hamsa_sim emits the manifest with the generated core and wrapper.
        subprocess.run(
            ["python3", "util/gen_hamsa_sim.py", "--enable-issue2",
             "0" if config == "H0" else "1"], cwd=ROOT, check=True
        )
        return "cv32e40p_manifest_hamsa.flist", "cv32e40p_core_hamsa", ""
    if config in {"H2-32", "H2-128"}:
        native = "1" if config == "H2-128" else "0"
        subprocess.run(["python3", "util/gen_hamsa_sim_h2.py", "--native", native],
                       cwd=ROOT, check=True)
        suffix = "h2_128" if native == "1" else "h2_32"
        # Backends that support parameter overrides can consume params. The
        # generated wrapper already bakes this value for wrapper-level synthesis.
        params = f"HAMSA_NATIVE_128_REFILL={native} HAMSA_ENABLE_ISSUE2=1"
        return f"cv32e40p_manifest_{suffix}.flist", "cv32e40p_core_hamsa_h2", params
    if config == "H2-5R3W":
        subprocess.run(["python3", "util/gen_hamsa_core_h2_5r3w.py"],
                       cwd=ROOT, check=True)
        return "cv32e40p_manifest_h2_5r3w.flist", "cv32e40p_core_hamsa_h2_5r3w", ""
    raise ValueError(config)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--configs", default="B0,H0,H1,H2-32,H2-128,H2-5R3W")
    ap.add_argument("--command", required=True,
                    help="shell command template using {manifest}/{top}/{config}/{outdir}/{params}")
    ap.add_argument("--out-dir", type=Path,
                    default=ROOT / "evaluation/results/ppa")
    ap.add_argument("--csv", type=Path,
                    default=ROOT / "evaluation/results/ppa.csv")
    args = ap.parse_args()

    configs = [x.strip() for x in args.configs.split(",") if x.strip()]
    args.out_dir.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, str]] = []

    for cfg in configs:
        manifest, top, params = prepare(cfg)
        out = (args.out_dir / cfg).resolve()
        out.mkdir(parents=True, exist_ok=True)
        mapping = {
            "manifest": str((ROOT / manifest).resolve()),
            "top": top,
            "config": cfg,
            "outdir": str(out),
            "params": params,
        }
        command = args.command.format(**mapping)
        print(f"[HAMSA-PPA] {cfg}: {command}")
        proc = subprocess.run(command, cwd=ROOT, shell=True)
        if proc.returncode:
            raise SystemExit(f"PPA backend failed for {cfg}: {proc.returncode}")

        row: dict[str, str] = {"configuration": cfg, "top": top, "manifest": manifest}
        result = out / "ppa.json"
        if result.exists():
            payload = json.loads(result.read_text())
            for key, value in payload.items():
                if isinstance(value, (int, float, str)):
                    row[str(key)] = str(value)
        rows.append(row)

    keys = ["configuration", "top", "manifest"]
    extras = sorted({k for row in rows for k in row if k not in keys})
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=keys + extras)
        writer.writeheader()
        writer.writerows(rows)
    print(f"[HAMSA-PPA] wrote {args.csv}")


if __name__ == "__main__":
    main()
