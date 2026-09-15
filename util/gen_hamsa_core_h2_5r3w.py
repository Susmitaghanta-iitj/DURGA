#!/usr/bin/env python3
"""Generate H2 full core using the native shared 5R3W register file.

This is the PPA/structural-ablation counterpart to the default H2 bring-up core,
which uses a mirrored shadow RF for Issue2 reads. The generated core replaces
ID with cv32e40p_id_stage_hamsa_5r3w and connects Issue2 directly to RF read
ports D/E and write port C. It also emits cv32e40p_manifest_h2_5r3w.flist for
lint/synthesis under exactly the same RTL source set as the mirrored-RF core.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "rtl" / "cv32e40p_core_hamsa_h2.sv"
DST = ROOT / "rtl" / "cv32e40p_core_hamsa_h2_5r3w.sv"
MANIFEST = ROOT / "cv32e40p_manifest_h2_5r3w.flist"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected one match, found {n}")
    return text.replace(old, new, 1)


def main() -> int:
    subprocess.run(["python3", str(ROOT / "util/gen_hamsa_id_stage_5r3w.py")], check=True)
    subprocess.run(["python3", str(ROOT / "util/gen_hamsa_core_h2.py")], check=True)
    text = SRC.read_text()

    text = replace_once(text, "module cv32e40p_core_hamsa_h2\n",
                        "module cv32e40p_core_hamsa_h2_5r3w\n", "rename core")
    text = replace_once(text, "  cv32e40p_id_stage #(\n",
                        "  cv32e40p_id_stage_hamsa_5r3w #(\n", "ID module")

    decl_anchor = "  cv32e40p_id_stage_hamsa_5r3w #(\n"
    decl = """  // Native HAMSA 5R3W Issue2 register-file ports.\n  logic [5:0]  hamsa_rf_raddr_d;\n  logic [5:0]  hamsa_rf_raddr_e;\n  logic [31:0] hamsa_rf_rdata_d;\n  logic [31:0] hamsa_rf_rdata_e;\n  logic        hamsa_rf_we_c;\n  logic [5:0]  hamsa_rf_waddr_c;\n  logic [31:0] hamsa_rf_wdata_c;\n\n""" + decl_anchor
    text = replace_once(text, decl_anchor, decl, "RF wire declarations")

    id_anchor = """      .regfile_alu_wdata_fw_i(hamsa_alu_wdata_fw),\n\n      // from ALU\n"""
    id_new = """      .regfile_alu_wdata_fw_i(hamsa_alu_wdata_fw),\n\n      .hamsa_raddr_d_i(hamsa_rf_raddr_d),\n      .hamsa_rdata_d_o(hamsa_rf_rdata_d),\n      .hamsa_raddr_e_i(hamsa_rf_raddr_e),\n      .hamsa_rdata_e_o(hamsa_rf_rdata_e),\n      .hamsa_waddr_c_i(hamsa_rf_waddr_c),\n      .hamsa_wdata_c_i(hamsa_rf_wdata_c),\n      .hamsa_we_c_i   (hamsa_rf_we_c),\n\n      // from ALU\n"""
    text = replace_once(text, id_anchor, id_new, "ID 5R3W connections")

    param_anchor = """  cv32e40p_hamsa_issue_cluster #(\n      .ENABLE_ISSUE2(HAMSA_ENABLE_ISSUE2)\n  ) hamsa_issue_cluster_i (\n"""
    param_new = """  cv32e40p_hamsa_issue_cluster #(\n      .ENABLE_ISSUE2(HAMSA_ENABLE_ISSUE2),\n      .NATIVE_5R3W  (1'b1)\n  ) hamsa_issue_cluster_i (\n"""
    text = replace_once(text, param_anchor, param_new, "cluster native-RF parameter")

    issue_anchor = """      .primary_ex_data_i          (regfile_alu_wdata_fw),\n      .arb_alu_we_o               (hamsa_alu_we_fw),\n"""
    issue_new = """      .primary_ex_data_i          (regfile_alu_wdata_fw),\n      .issue2_rs1_addr_o          (hamsa_rf_raddr_d),\n      .issue2_rs2_addr_o          (hamsa_rf_raddr_e),\n      .issue2_rs1_data_i          (hamsa_rf_rdata_d),\n      .issue2_rs2_data_i          (hamsa_rf_rdata_e),\n      .issue2_rf_we_o             (hamsa_rf_we_c),\n      .issue2_rf_addr_o           (hamsa_rf_waddr_c),\n      .issue2_rf_data_o           (hamsa_rf_wdata_c),\n      .arb_alu_we_o               (hamsa_alu_we_fw),\n"""
    text = replace_once(text, issue_anchor, issue_new, "cluster RF connections")

    DST.write_text(text)

    manifest = (ROOT / "cv32e40p_manifest.flist").read_text()
    manifest = replace_once(manifest,
                            "${DESIGN_RTL_DIR}/cv32e40p_id_stage.sv\n",
                            "${DESIGN_RTL_DIR}/cv32e40p_id_stage_hamsa_5r3w.sv\n",
                            "manifest ID")
    manifest = replace_once(manifest,
                            "${DESIGN_RTL_DIR}/cv32e40p_core.sv\n",
                            "${DESIGN_RTL_DIR}/cv32e40p_core_hamsa_h2_5r3w.sv\n",
                            "manifest core")
    # Core-only PPA/lint manifest: wrapper stays baseline but is not selected as
    # top, so no interface change is required for the RF comparison.
    MANIFEST.write_text(manifest)

    print(f"generated {DST.relative_to(ROOT)} and {MANIFEST.name}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"gen_hamsa_core_h2_5r3w.py: ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
