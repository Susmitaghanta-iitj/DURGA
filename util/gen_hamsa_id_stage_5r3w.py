#!/usr/bin/env python3
"""Generate cv32e40p_id_stage_hamsa_5r3w from the preserved ID stage.

The variant replaces the baseline 3R2W register file with the shared 5R3W
implementation and exposes two Issue2 read ports plus the dedicated third write
port. All primary-lane decode/control logic remains byte-for-byte inherited from
cv32e40p_id_stage.sv.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "rtl" / "cv32e40p_id_stage.sv"
DST = ROOT / "rtl" / "cv32e40p_id_stage_hamsa_5r3w.sv"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected one match, found {n}")
    return text.replace(old, new, 1)


def main() -> int:
    text = SRC.read_text()
    text = replace_once(text, "module cv32e40p_id_stage\n",
                        "module cv32e40p_id_stage_hamsa_5r3w\n", "rename")

    port_anchor = """    input logic [31:0] regfile_alu_wdata_fw_i,\n\n    // from ALU\n"""
    port_new = """    input logic [31:0] regfile_alu_wdata_fw_i,\n\n    // HAMSA Issue2 shared-register-file ports\n    input  logic [ 5:0] hamsa_raddr_d_i,\n    output logic [31:0] hamsa_rdata_d_o,\n    input  logic [ 5:0] hamsa_raddr_e_i,\n    output logic [31:0] hamsa_rdata_e_o,\n    input  logic [ 5:0] hamsa_waddr_c_i,\n    input  logic [31:0] hamsa_wdata_c_i,\n    input  logic        hamsa_we_c_i,\n\n    // from ALU\n"""
    text = replace_once(text, port_anchor, port_new, "HAMSA RF ports")

    old = """  cv32e40p_register_file #(\n      .ADDR_WIDTH(6),\n      .DATA_WIDTH(32),\n      .FPU       (FPU),\n      .PULP_ZFINX(PULP_ZFINX)\n  ) register_file_i (\n      .clk  (clk),\n      .rst_n(rst_n),\n\n      .scan_cg_en_i(scan_cg_en_i),\n\n      // Read port a\n      .raddr_a_i(regfile_addr_ra_id),\n      .rdata_a_o(regfile_data_ra_id),\n\n      // Read port b\n      .raddr_b_i(regfile_addr_rb_id),\n      .rdata_b_o(regfile_data_rb_id),\n\n      // Read port c\n      .raddr_c_i(regfile_addr_rc_id),\n      .rdata_c_o(regfile_data_rc_id),\n\n      // Write port a\n      .waddr_a_i(regfile_waddr_wb_i),\n      .wdata_a_i(regfile_wdata_wb_i),\n      .we_a_i   (regfile_we_wb_i),\n\n      // Write port b\n      .waddr_b_i(regfile_alu_waddr_fw_i),\n      .wdata_b_i(regfile_alu_wdata_fw_i),\n      .we_b_i   (regfile_alu_we_fw_i)\n  );\n"""
    new = """  cv32e40p_register_file_5r3w #(\n      .ADDR_WIDTH(6),\n      .DATA_WIDTH(32),\n      .FPU       (FPU),\n      .PULP_ZFINX(PULP_ZFINX)\n  ) register_file_i (\n      .clk  (clk),\n      .rst_n(rst_n),\n      .scan_cg_en_i(scan_cg_en_i),\n\n      .raddr_a_i(regfile_addr_ra_id),\n      .rdata_a_o(regfile_data_ra_id),\n      .raddr_b_i(regfile_addr_rb_id),\n      .rdata_b_o(regfile_data_rb_id),\n      .raddr_c_i(regfile_addr_rc_id),\n      .rdata_c_o(regfile_data_rc_id),\n      .raddr_d_i(hamsa_raddr_d_i),\n      .rdata_d_o(hamsa_rdata_d_o),\n      .raddr_e_i(hamsa_raddr_e_i),\n      .rdata_e_o(hamsa_rdata_e_o),\n\n      .waddr_a_i(regfile_waddr_wb_i),\n      .wdata_a_i(regfile_wdata_wb_i),\n      .we_a_i   (regfile_we_wb_i),\n      .waddr_b_i(regfile_alu_waddr_fw_i),\n      .wdata_b_i(regfile_alu_wdata_fw_i),\n      .we_b_i   (regfile_alu_we_fw_i),\n      .waddr_c_i(hamsa_waddr_c_i),\n      .wdata_c_i(hamsa_wdata_c_i),\n      .we_c_i   (hamsa_we_c_i)\n  );\n"""
    text = replace_once(text, old, new, "replace register file")

    DST.write_text(text)
    print(f"generated {DST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"gen_hamsa_id_stage_5r3w.py: ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
