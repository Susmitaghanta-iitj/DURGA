#!/usr/bin/env python3
"""Generate the full-core H2 HAMSA CV32E40P variant.

Unlike gen_hamsa_core.py (H0/H1 backend bring-up), H2 replaces the original
word-oriented cv32e40p_if_stage with cv32e40p_hamsa_if_stage.  The replacement
preserves the original redirect inputs and target-selection semantics while
using the 8x128-bit L0/RV32C dual extractor and Inst2 replay protocol.

Generated output: rtl/cv32e40p_core_hamsa_h2.sv

Parameters added to the generated core:
  HAMSA_ENABLE_ISSUE2       -- secondary lane enable
  HAMSA_NATIVE_128_REFILL   -- 0: four 32-bit beats, 1: native 128-bit line
  HAMSA_L0_LINES            -- number of 128-bit direct-mapped L0 lines

The generated core also exposes an optional native 128-bit line interface.
Legacy wrappers may leave those ports unconnected when HAMSA_NATIVE_128_REFILL=0.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "rtl" / "cv32e40p_core.sv"
DST = ROOT / "rtl" / "cv32e40p_core_hamsa_h2.sv"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {n}")
    return text.replace(old, new, 1)


def insert_before_once(text: str, anchor: str, payload: str, label: str) -> str:
    n = text.count(anchor)
    if n != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {n}")
    return text.replace(anchor, payload + anchor, 1)


def replace_region(text: str, start: str, end: str, payload: str, label: str) -> str:
    s = text.find(start)
    if s < 0:
        raise RuntimeError(f"{label}: start anchor missing")
    e = text.find(end, s)
    if e < 0:
        raise RuntimeError(f"{label}: end anchor missing")
    return text[:s] + payload + text[e:]


def main() -> int:
    text = SRC.read_text()

    text = replace_once(text, "module cv32e40p_core\n",
                        "module cv32e40p_core_hamsa_h2\n", "rename top")

    text = replace_once(
        text,
        "    parameter NUM_MHPMCOUNTERS = 1\n",
        "    parameter NUM_MHPMCOUNTERS = 1,\n"
        "    parameter bit HAMSA_ENABLE_ISSUE2 = 1'b1,\n"
        "    parameter bit HAMSA_NATIVE_128_REFILL = 1'b0,\n"
        "    parameter int HAMSA_L0_LINES = 8\n",
        "HAMSA H2 parameters",
    )

    # Native line-refill ports are additional to the legacy 32-bit instruction
    # interface.  They are active only when HAMSA_NATIVE_128_REFILL=1.
    instr_ports = """    output logic [31:0] instr_addr_o,\n    input  logic [31:0] instr_rdata_i,\n\n"""
    instr_ports_new = instr_ports + """    // HAMSA H2 native 128-bit instruction-line interface\n    output logic         hamsa_line_req_o,\n    output logic [31:0]  hamsa_line_addr_o,\n    input  logic         hamsa_line_gnt_i,\n    input  logic         hamsa_line_rvalid_i,\n    input  logic [127:0] hamsa_line_rdata_i,\n\n"""
    text = replace_once(text, instr_ports, instr_ports_new, "native line ports")

    ifid_old = """  logic        instr_valid_id;\n  logic [31:0] instr_rdata_id;  // Instruction sampled inside IF stage\n  logic        is_compressed_id;\n  logic        illegal_c_insn_id;\n  logic        is_fetch_failed_id;\n"""
    ifid_new = ifid_old + """
  // HAMSA H2 younger instruction and L0 observability.
  logic        hamsa_inst2_valid;
  logic [31:0] hamsa_inst2;
  logic [31:0] hamsa_inst2_pc;
  logic        hamsa_inst2_compressed;
  logic        hamsa_inst2_illegal_c;
  logic        hamsa_inst2_consumed;
  logic        hamsa_pair_fire;
  logic        hamsa_l0_lookup;
  logic        hamsa_l0_hit;
  logic        hamsa_l0_refill;
"""
    text = replace_once(text, ifid_old, ifid_new, "H2 IF declarations")

    rf_old = """  logic        [                 5:0]       regfile_alu_waddr_fw;\n  logic                                     regfile_alu_we_fw;\n  logic        [                31:0]       regfile_alu_wdata_fw;\n"""
    rf_new = rf_old + """
  logic        [                 5:0]       hamsa_alu_waddr_fw;
  logic                                     hamsa_alu_we_fw;
  logic        [                31:0]       hamsa_alu_wdata_fw;
  logic                                     hamsa_issue2_pending;
  logic                                     hamsa_issue2_blocked;
  logic                                     hamsa_issue2_retired;
  logic                                     hamsa_issue2_block_raw;
  logic                                     hamsa_issue2_block_waw;
  logic                                     hamsa_issue2_block_unsupported;
  logic                                     hamsa_issue2_block_serializing;
  logic                                     hamsa_issue2_block_busy;
  logic                                     hamsa_issue2_block_decode;
"""
    text = replace_once(text, rf_old, rf_new, "H2 RF declarations")

    # Replace the complete original IF-stage instance.  The ID-stage marker is
    # used as a stable end anchor so changes inside the old IF port list cannot
    # silently leave two fetch engines instantiated.
    if_start = "  cv32e40p_if_stage #(\n"
    id_marker = "  cv32e40p_id_stage #(\n"
    h2_if_block = r'''  cv32e40p_hamsa_if_stage #(
      .PULP_XPULP          (PULP_XPULP),
      .PULP_SECURE         (PULP_SECURE),
      .FPU                 (FPU),
      .L0_LINES            (HAMSA_L0_LINES),
      .NATIVE_128_REFILL   (HAMSA_NATIVE_128_REFILL)
  ) if_stage_i (
      .clk                 (clk),
      .rst_n               (rst_ni),
      .m_trap_base_addr_i  (mtvec),
      .u_trap_base_addr_i  (utvec),
      .trap_addr_mux_i     (trap_addr_mux),
      .boot_addr_i         (boot_addr_i[31:0]),
      .dm_exception_addr_i (dm_exception_addr_i[31:0]),
      .dm_halt_addr_i      (dm_halt_addr_i[31:0]),
      .req_i               (instr_req_int),

      .instr_req_o         (instr_req_pmp),
      .instr_addr_o        (instr_addr_pmp),
      .instr_gnt_i         (instr_gnt_pmp),
      .instr_rvalid_i      (instr_rvalid_i),
      .instr_rdata_i       (instr_rdata_i),
      .instr_err_i         (1'b0),
      .instr_err_pmp_i     (instr_err_pmp),

      .line_req_o          (hamsa_line_req_o),
      .line_addr_o         (hamsa_line_addr_o),
      .line_gnt_i          (hamsa_line_gnt_i),
      .line_rvalid_i       (hamsa_line_rvalid_i),
      .line_rdata_i        (hamsa_line_rdata_i),

      .instr_valid_id_o    (instr_valid_id),
      .instr_rdata_id_o    (instr_rdata_id),
      .is_compressed_id_o  (is_compressed_id),
      .illegal_c_insn_id_o (illegal_c_insn_id),
      .pc_if_o             (pc_if),
      .pc_id_o             (pc_id),
      .is_fetch_failed_o   (is_fetch_failed_id),

      .inst2_valid_o       (hamsa_inst2_valid),
      .inst2_rdata_o       (hamsa_inst2),
      .inst2_pc_o          (hamsa_inst2_pc),
      .inst2_compressed_o  (hamsa_inst2_compressed),
      .inst2_illegal_c_o   (hamsa_inst2_illegal_c),
      .inst2_consumed_i    (hamsa_inst2_consumed),

      .clear_instr_valid_i (clear_instr_valid),
      .pc_set_i            (pc_set),
      .mepc_i              (mepc),
      .uepc_i              (uepc),
      .depc_i              (depc),
      .pc_mux_i            (pc_mux_id),
      .exc_pc_mux_i        (exc_pc_mux_id),
      .m_exc_vec_pc_mux_i  (m_exc_vec_pc_mux_id),
      .u_exc_vec_pc_mux_i  (u_exc_vec_pc_mux_id),
      .csr_mtvec_init_o    (csr_mtvec_init),
      .jump_target_id_i    (jump_target_id),
      .jump_target_ex_i    (jump_target_ex),
      .hwlp_jump_i         (hwlp_jump),
      .hwlp_target_i       (hwlp_target),
      .halt_if_i           (halt_if),
      .id_ready_i          (id_ready),
      .if_busy_o           (if_busy),
      .perf_imiss_o        (perf_imiss),
      .l0_lookup_o         (hamsa_l0_lookup),
      .l0_hit_o            (hamsa_l0_hit),
      .l0_refill_o         (hamsa_l0_refill)
  );

  assign hamsa_pair_fire = instr_valid_id && id_ready;

'''
    text = replace_region(text, if_start, id_marker, h2_if_block, "replace IF stage")

    fw_old = """      .regfile_alu_waddr_fw_i(regfile_alu_waddr_fw),\n      .regfile_alu_we_fw_i   (regfile_alu_we_fw),\n      .regfile_alu_wdata_fw_i(regfile_alu_wdata_fw),\n"""
    fw_new = """      .regfile_alu_waddr_fw_i(hamsa_alu_waddr_fw),\n      .regfile_alu_we_fw_i   (hamsa_alu_we_fw),\n      .regfile_alu_wdata_fw_i(hamsa_alu_wdata_fw),\n"""
    text = replace_once(text, fw_old, fw_new, "H2 RF write arbitration")

    issue_block = r'''
  // -------------------------------------------------------------------------
  // HAMSA H2 asymmetric secondary issue cluster
  // -------------------------------------------------------------------------
  cv32e40p_hamsa_issue_cluster #(
      .ENABLE_ISSUE2(HAMSA_ENABLE_ISSUE2)
  ) hamsa_issue_cluster_i (
      .clk                        (clk),
      .rst_n                      (rst_ni),
      .flush_i                    (pc_set),
      .pair_fire_i                (hamsa_pair_fire),
      .primary_commit_safe_i      (ex_valid && !data_err_pmp),
      .inst1_valid_i              (instr_valid_id),
      .inst1_i                    (instr_rdata_id),
      .inst2_valid_i              (hamsa_inst2_valid && !hamsa_inst2_illegal_c),
      .inst2_i                    (hamsa_inst2),
      .primary_wb_we_i            (regfile_we_wb),
      .primary_wb_addr_i          (regfile_waddr_fw_wb_o),
      .primary_wb_data_i          (regfile_wdata),
      .primary_alu_we_i           (regfile_alu_we_fw),
      .primary_alu_addr_i         (regfile_alu_waddr_fw),
      .primary_alu_data_i         (regfile_alu_wdata_fw),
      .primary_ex_we_i            (regfile_alu_we_fw),
      .primary_ex_addr_i          (regfile_alu_waddr_fw),
      .primary_ex_data_i          (regfile_alu_wdata_fw),
      .arb_alu_we_o               (hamsa_alu_we_fw),
      .arb_alu_addr_o             (hamsa_alu_waddr_fw),
      .arb_alu_data_o             (hamsa_alu_wdata_fw),
      .inst2_consumed_o           (hamsa_inst2_consumed),
      .issue2_pending_o           (hamsa_issue2_pending),
      .issue2_retired_o           (hamsa_issue2_retired),
      .issue2_blocked_o           (hamsa_issue2_blocked),
      .issue2_block_raw_o         (hamsa_issue2_block_raw),
      .issue2_block_waw_o         (hamsa_issue2_block_waw),
      .issue2_block_unsupported_o (hamsa_issue2_block_unsupported),
      .issue2_block_serializing_o (hamsa_issue2_block_serializing),
      .issue2_block_busy_o        (hamsa_issue2_block_busy),
      .issue2_block_decode_o      (hamsa_issue2_block_decode)
  );

  logic hamsa_unused_status;
  assign hamsa_unused_status = ^hamsa_inst2_pc ^ hamsa_inst2_compressed ^
                               hamsa_issue2_pending ^ hamsa_issue2_blocked ^
                               hamsa_issue2_retired ^ hamsa_l0_refill;

'''
    text = insert_before_once(text, "  cv32e40p_load_store_unit #(\n",
                              issue_block, "H2 issue cluster")

    DST.write_text(text)
    print(f"generated {DST.relative_to(ROOT)} ({len(text)} bytes)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"gen_hamsa_core_h2.py: ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
