#!/usr/bin/env python3
"""Run a CV32E40P example-testbench firmware in B0 or HAMSA mode.

B0 uses an evaluation-only generated top that leaves the baseline RTL untouched
but emits the same HAMSA_METRIC log contract as H1. H0 and H2 remain reserved
until their explicit architectural switches/interfaces are complete.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TB = ROOT / "example_tb" / "core"


def run(cmd: list[str], cwd: Path) -> int:
    print("[HAMSA]", " ".join(cmd))
    return subprocess.run(cmd, cwd=cwd).returncode


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("configuration", choices=["B0", "H0", "H1", "H2"])
    p.add_argument("firmware", type=Path)
    p.add_argument("--maxcycles", type=int, default=20_000_000)
    p.add_argument("--vsim-flags", default="")
    args = p.parse_args()

    fw = args.firmware.resolve()
    if not fw.exists():
        raise SystemExit(f"firmware not found: {fw}")

    if args.configuration in {"H0", "H2"}:
        raise SystemExit(
            f"{args.configuration} is reserved but not executable yet: "
            "H0 needs an Issue2-disable build switch and H2 needs the 128-bit "
            "L0 memory interface wired into the SoC/testbench. Use B0 or H1."
        )

    if args.configuration == "H1":
        subprocess.run(["python3", str(ROOT / "util" / "gen_hamsa_sim.py")],
                       cwd=ROOT, check=True)
        manifest = str(ROOT / "cv32e40p_manifest_hamsa.flist")
        tb_top = "tb_top_hamsa.sv"
        vopt_top = "tb_top_hamsa_vopt"
    else:
        subprocess.run(["python3", str(ROOT / "util" / "gen_baseline_eval_tb.py")],
                       cwd=ROOT, check=True)
        manifest = str(ROOT / "cv32e40p_manifest.flist")
        tb_top = "tb_top_eval.sv"
        vopt_top = "tb_top_eval_vopt"

    flags = f'+firmware={fw} +maxcycles={args.maxcycles} {args.vsim_flags}'.strip()

    make_cmd = [
        "make", "vsim-run",
        f"CV_CORE_MANIFEST={manifest}",
        f"RTLSRC_TB_TOP={tb_top}",
        f"RTLSRC_VLOG_TB_TOP={Path(tb_top).stem}",
        f"RTLSRC_VOPT_TB_TOP={vopt_top}",
        f"VSIM_FLAGS={flags}",
    ]
    rc = run(make_cmd, TB)
    if rc:
        raise SystemExit(rc)


if __name__ == "__main__":
    main()
