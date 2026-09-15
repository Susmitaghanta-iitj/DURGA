#!/usr/bin/env python3
"""Run identical firmware across B0/H0/H1/H2 and compare architectural results.

For ordinary programs the runner requires every configuration to terminate with
EXIT SUCCESS/ALL TESTS PASSED. For RISC-V compliance-style programs that dump a
signature, pass --compare-signatures; each run receives a unique +signature=
path and the resulting files are compared byte-for-byte against B0.
"""
from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "evaluation" / "run_example_vsim.py"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("firmware", nargs="+", type=Path)
    ap.add_argument("--configs", default="B0,H0,H1,H2-32,H2-128")
    ap.add_argument("--maxcycles", type=int, default=20_000_000)
    ap.add_argument("--compare-signatures", action="store_true")
    ap.add_argument("--out-dir", type=Path,
                    default=ROOT / "evaluation/results/regression")
    args = ap.parse_args()

    configs = [c.strip() for c in args.configs.split(",") if c.strip()]
    args.out_dir.mkdir(parents=True, exist_ok=True)

    failures: list[str] = []
    for fw_in in args.firmware:
        fw = fw_in.resolve()
        if not fw.exists():
            failures.append(f"missing firmware: {fw}")
            continue

        name = fw.stem
        signatures: dict[str, bytes] = {}
        for cfg in configs:
            log_path = args.out_dir / f"{name}__{cfg}.log"
            sig_path = args.out_dir / f"{name}__{cfg}.signature"
            cmd = [
                "python3", str(RUN), cfg, str(fw),
                "--maxcycles", str(args.maxcycles),
            ]
            if args.compare_signatures:
                cmd += ["--vsim-flags", f"+signature={sig_path}"]

            print("[HAMSA-REG]", " ".join(cmd))
            proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
            text = proc.stdout + ("\n" if proc.stdout and proc.stderr else "") + proc.stderr
            log_path.write_text(text)
            print(text, end="")

            success_marker = ("EXIT SUCCESS" in text) or ("ALL TESTS PASSED" in text)
            if proc.returncode != 0 or not success_marker:
                failures.append(f"{name}/{cfg}: failed; see {log_path}")
                continue

            if args.compare_signatures:
                if not sig_path.exists():
                    failures.append(f"{name}/{cfg}: no signature produced")
                else:
                    signatures[cfg] = sig_path.read_bytes()

        if args.compare_signatures and "B0" in signatures:
            golden = signatures["B0"]
            for cfg, sig in signatures.items():
                if cfg != "B0" and sig != golden:
                    failures.append(f"{name}/{cfg}: signature differs from B0")

    if failures:
        print("\n[HAMSA-REG] FAIL")
        for failure in failures:
            print(" -", failure)
        raise SystemExit(1)

    print("[HAMSA-REG] PASS: all selected configurations match expected architectural termination")


if __name__ == "__main__":
    main()
