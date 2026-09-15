#!/usr/bin/env python3
"""Run one CV32E40P/HAMSA/SPARV configuration in the example testbench.

Configurations:
  B0         original CV32E40P + evaluation-only counters
  H0         HAMSA integration, Issue2 disabled
  H1         HAMSA integration, Issue2 enabled
  H2-32      HAMSA H2, 8x128-bit L0 with four 32-bit refill beats
  H2-128     HAMSA H2, native 128-bit line refill
  SPARV-32   SPARV prefetch + accelerated MUL/MAC/DOTP, four 32-bit beats
  SPARV-128  same SPARV core, native 128-bit line refill
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TB = ROOT / "example_tb" / "core"


def run(cmd: list[str], cwd: Path) -> int:
    print("[EVAL]", " ".join(cmd))
    return subprocess.run(cmd, cwd=cwd).returncode


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument(
        "configuration",
        choices=["B0", "H0", "H1", "H2", "H2-32", "H2-128",
                 "SPARV-32", "SPARV-128"],
    )
    p.add_argument("firmware", type=Path)
    p.add_argument("--maxcycles", type=int, default=20_000_000)
    p.add_argument("--vsim-flags", default="")
    args = p.parse_args()

    fw = args.firmware.resolve()
    if not fw.exists():
        raise SystemExit(f"firmware not found: {fw}")

    cfg = "H2-32" if args.configuration == "H2" else args.configuration

    if cfg in {"H0", "H1"}:
        enable_issue2 = "1" if cfg == "H1" else "0"
        subprocess.run(
            ["python3", str(ROOT / "util" / "gen_hamsa_sim.py"),
             "--enable-issue2", enable_issue2], cwd=ROOT, check=True)
        manifest = str(ROOT / "cv32e40p_manifest_hamsa.flist")
        tb_top = "tb_top_hamsa.sv"
        vopt_top = "tb_top_hamsa_vopt"
    elif cfg in {"H2-32", "H2-128"}:
        native = "1" if cfg == "H2-128" else "0"
        suffix = "h2_128" if cfg == "H2-128" else "h2_32"
        subprocess.run(
            ["python3", str(ROOT / "util" / "gen_hamsa_sim_h2.py"),
             "--native", native], cwd=ROOT, check=True)
        manifest = str(ROOT / f"cv32e40p_manifest_{suffix}.flist")
        tb_top = f"tb_top_{suffix}.sv"
        vopt_top = f"tb_top_{suffix}_vopt"
    elif cfg in {"SPARV-32", "SPARV-128"}:
        native = "1" if cfg == "SPARV-128" else "0"
        suffix = "sparv_128" if cfg == "SPARV-128" else "sparv_32"
        subprocess.run(
            ["python3", str(ROOT / "util" / "gen_sparv_sim.py"),
             "--native", native], cwd=ROOT, check=True)
        manifest = str(ROOT / f"cv32e40p_manifest_{suffix}.flist")
        tb_top = f"tb_top_{suffix}.sv"
        vopt_top = f"tb_top_{suffix}_vopt"
    else:
        subprocess.run(
            ["python3", str(ROOT / "util" / "gen_baseline_eval_tb.py")],
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
