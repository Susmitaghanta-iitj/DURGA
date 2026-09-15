#!/usr/bin/env python3
"""Generate a SPARV full-core variant on top of the verified HAMSA H2 core.

The HAMSA H2 generator remains the source of truth for dual-issue backend and
architectural integration. SPARV replaces the H2 fetch stage with
cv32e40p_sparv_if_stage and replaces the baseline EX-stage multiplier instance
with cv32e40p_sparv_mult. Existing CV32E40P/Xpulp decode therefore drives the
SPARV datapath through the already-defined MUL_MAC32/MUL_DOT8/MUL_DOT16
micro-operations; no unpublished opcode encoding is invented here.

Generated outputs:
  rtl/cv32e40p_sparv_ex_stage.sv
  rtl/cv32e40p_core_sparv.sv
  cv32e40p_manifest_sparv.flist
"""

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected one match, found {n}")
    return text.replace(old, new, 1)


def generate_ex_stage() -> None:
    src = RTL / "cv32e40p_ex_stage.sv"
    dst = RTL / "cv32e40p_sparv_ex_stage.sv"
    text = src.read_text()
    text = replace_once(text,
                        "module cv32e40p_ex_stage\n",
                        "module cv32e40p_sparv_ex_stage\n",
                        "EX-stage module rename")
    text = replace_once(text,
                        "  cv32e40p_mult mult_i (\n",
                        "  cv32e40p_sparv_mult mult_i (\n",
                        "SPARV multiplier replacement")
    dst.write_text(text)


def main() -> int:
    subprocess.run(["python3", str(ROOT / "util" / "gen_hamsa_core_h2.py")],
                   cwd=ROOT, check=True)

    generate_ex_stage()

    src = RTL / "cv32e40p_core_hamsa_h2.sv"
    dst = RTL / "cv32e40p_core_sparv.sv"
    text = src.read_text()

    text = replace_once(text,
                        "module cv32e40p_core_hamsa_h2\n",
                        "module cv32e40p_core_sparv\n",
                        "top rename")
    text = replace_once(text,
                        "cv32e40p_hamsa_if_stage #(\n",
                        "cv32e40p_sparv_if_stage #(\n",
                        "SPARV IF replacement")
    text = replace_once(text,
                        "cv32e40p_ex_stage #(\n",
                        "cv32e40p_sparv_ex_stage #(\n",
                        "SPARV EX-stage replacement")

    dst.write_text(text)

    manifest = (ROOT / "cv32e40p_manifest.flist").read_text()
    manifest = replace_once(manifest,
                            "${DESIGN_RTL_DIR}/cv32e40p_core.sv\n",
                            "${DESIGN_RTL_DIR}/cv32e40p_core_sparv.sv\n",
                            "manifest core")

    sparv_sources = """${DESIGN_RTL_DIR}/cv32e40p_sparv_prefetch_ctrl.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_prefetch_directory.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_refill_arbiter.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_refill_manager.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_l0_prefetch_meta.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_prefetch_counters.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_mac_dotp_ref.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_mac_dotp_engine.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_accel_lane.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_mult.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_ex_stage.sv
${DESIGN_RTL_DIR}/cv32e40p_sparv_if_stage.sv
"""
    anchor = "${DESIGN_RTL_DIR}/cv32e40p_hamsa_if_stage.sv\n"
    if anchor not in manifest:
        raise RuntimeError("manifest insertion anchor missing")
    manifest = manifest.replace(anchor, anchor + sparv_sources, 1)

    (ROOT / "cv32e40p_manifest_sparv.flist").write_text(manifest)
    print(f"generated {(RTL / 'cv32e40p_sparv_ex_stage.sv').relative_to(ROOT)}")
    print(f"generated {dst.relative_to(ROOT)}")
    print("generated cv32e40p_manifest_sparv.flist")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"gen_sparv_core.py: ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
