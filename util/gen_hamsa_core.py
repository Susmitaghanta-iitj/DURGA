#!/usr/bin/env python3
"""Generate a HAMSA-integrated CV32E40P top from the preserved core source.

The generator avoids maintaining a 48-kB fork of cv32e40p_core.sv while the
prototype is evolving.  It performs checked, deterministic substitutions and
emits rtl/cv32e40p_core_hamsa.sv.  Every anchor must match exactly once; a source
layout change therefore fails loudly instead of silently producing bad RTL.

Current generated integration uses the existing 32-bit CV32E40P frontend plus
cv32e40p_dual_fetch_pair_buffer for bring-up.  The 128-bit L0 frontend remains a
separate drop-in block for the final memory-interface widening milestone.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "rtl" / "cv32e40p_core.sv"
DST = ROOT / "rtl" / "cv32e40p_core_hamsa.sv"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def insert_before_once(text: str, anchor: str, payload: str, label: str) -> str:
    count = text.count(anchor)
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {count}")
    return text.replace(anchor, payload + anchor, 1)


def main() -> int:
    text = SRC.read_text()

    text = replace_once(
        text,
        "module cv32e40p_core\n",
        "module cv32e40p_core_hamsa\n",
        "rename top",
    )

    ifid_old = """  logic        instr_valid_id;\n  logic [31:0] instr_rdata_id;  // Instruction sampled inside IF stage\n  logic        is_compressed_id;\n  logic        illegal_c_insn_id;\n  logic        is_fetch_failed_id;\n"""
    ifid_new = ifid_old + """
  // HAMSA bring-up frontend wires. The original IF stage still fetches one
  // instruction at a time; the pair buffer combines two sequential RV32
  // instructions and replays Inst2 whenever the secondary lane cannot consume
  // it. This preserves architectural correctness while backend integration is
  // validated before enabling the 128-bit L0 interface.
  logic        hamsa_if_instr_valid;
  logic [31:0] hamsa_if_instr;
  logic [31:0] hamsa_if_pc;
  logic        hamsa_if_compressed;
  logic        hamsa_if_illegal_c;
  logic        hamsa_if_fetch_failed;
  logic        hamsa_pair_in_ready;
  logic        hamsa_inst2_valid;
  logic [31:0] hamsa_inst2;
  logic [31:0] hamsa_inst2_pc;
  logic        hamsa_inst2_consumed;
  logic        hamsa_pair_fire;
"""
    text = replace_once(text, ifid_old, ifid_new, "IF/ID declarations")

    rf_old = """  logic        [                 5:0]       regfile_alu_waddr_fw;\n  logic                                     regfile_alu_we_fw;\n  logic        [                31:0]       regfile_alu_wdata_fw;\n"""
    rf_new = rf_old + """
  // HAMSA arbitration result presented to the legacy ID-stage RF write port.
  logic        [                 5:0]       hamsa_alu_waddr_fw;
  logic                                     hamsa_alu_we_fw;
  logic        [                31:0]       hamsa_alu_wdata_fw;
  logic                                     hamsa_issue2_pending;
  logic                                     hamsa_issue2_blocked;
"""
    text = replace_once(text, rf_old, rf_new, "RF forwarding declarations")

    if_outputs_old = """      .instr_valid_id_o (instr_valid_id),\n      .instr_rdata_id_o (instr_rdata_id),\n      .is_fetch_failed_o(is_fetch_failed_id),\n"""
    if_outputs_new = """      .instr_valid_id_o (hamsa_if_instr_valid),\n      .instr_rdata_id_o (hamsa_if_instr),\n      .is_fetch_failed_o(hamsa_if_fetch_failed),\n"""
    text = replace_once(text, if_outputs_old, if_outputs_new, "IF data outputs")

    text = replace_once(
        text,
        "      .pc_id_o(pc_id),\n",
        "      .pc_id_o(hamsa_if_pc),\n",
        "IF PC output",
    )
    text = replace_once(
        text,
        "      .is_compressed_id_o (is_compressed_id),\n      .illegal_c_insn_id_o(illegal_c_insn_id),\n",
        "      .is_compressed_id_o (hamsa_if_compressed),\n      .illegal_c_insn_id_o(hamsa_if_illegal_c),\n",
        "IF metadata outputs",
    )
    text = replace_once(
        text,
        "      .id_ready_i(id_ready),\n",
        "      .id_ready_i(hamsa_pair_in_ready),\n",
        "IF ready input",
    )

    pair_block = r'''
  // -------------------------------------------------------------------------
  // HAMSA sequential pair assembly / replay buffer
  // -------------------------------------------------------------------------
  cv32e40p_dual_fetch_pair_buffer hamsa_pair_buffer_i (
      .clk                     (clk),
      .rst_n                   (rst_ni),
      .flush_i                 (pc_set),
      .in_valid_i              (hamsa_if_instr_valid),
      .in_instr_i              (hamsa_if_instr),
      .in_pc_i                 (hamsa_if_pc),
      .in_compressed_i         (hamsa_if_compressed),
      .in_illegal_c_i          (hamsa_if_illegal_c),
      .in_fetch_failed_i       (hamsa_if_fetch_failed),
      .in_ready_o              (hamsa_pair_in_ready),
      .out_valid_o             (instr_valid_id),
      .out_inst1_o             (instr_rdata_id),
      .out_pc1_o               (pc_id),
      .out_inst1_compressed_o  (is_compressed_id),
      .out_inst1_illegal_c_o   (illegal_c_insn_id),
      .out_inst1_fetch_failed_o(is_fetch_failed_id),
      .out_inst2_valid_o       (hamsa_inst2_valid),
      .out_inst2_o             (hamsa_inst2),
      .out_pc2_o               (hamsa_inst2_pc),
      .out_ready_i             (id_ready),
      .out_inst2_consumed_i    (hamsa_inst2_consumed)
  );

  assign hamsa_pair_fire = instr_valid_id && id_ready;

'''
    text = insert_before_once(
        text,
        "  cv32e40p_id_stage #(\n",
        pair_block,
        "ID-stage insertion",
    )

    fw_old = """      .regfile_alu_waddr_fw_i(regfile_alu_waddr_fw),\n      .regfile_alu_we_fw_i   (regfile_alu_we_fw),\n      .regfile_alu_wdata_fw_i(regfile_alu_wdata_fw),\n"""
    fw_new = """      .regfile_alu_waddr_fw_i(hamsa_alu_waddr_fw),\n      .regfile_alu_we_fw_i   (hamsa_alu_we_fw),\n      .regfile_alu_wdata_fw_i(hamsa_alu_wdata_fw),\n"""
    text = replace_once(text, fw_old, fw_new, "ID RF write arbitration")

    issue_block = r'''
  // -------------------------------------------------------------------------
  // HAMSA asymmetric secondary issue cluster
  // -------------------------------------------------------------------------
  cv32e40p_hamsa_issue_cluster hamsa_issue_cluster_i (
      .clk               (clk),
      .rst_n             (rst_ni),
      .flush_i           (pc_set),
      .pair_fire_i       (hamsa_pair_fire),
      .inst1_valid_i     (instr_valid_id),
      .inst1_i           (instr_rdata_id),
      .inst2_valid_i     (hamsa_inst2_valid),
      .inst2_i           (hamsa_inst2),
      .primary_wb_we_i   (regfile_we_wb),
      .primary_wb_addr_i (regfile_waddr_fw_wb_o),
      .primary_wb_data_i (regfile_wdata),
      .primary_alu_we_i  (regfile_alu_we_fw),
      .primary_alu_addr_i(regfile_alu_waddr_fw),
      .primary_alu_data_i(regfile_alu_wdata_fw),
      .primary_ex_we_i   (regfile_alu_we_fw),
      .primary_ex_addr_i (regfile_alu_waddr_fw),
      .primary_ex_data_i (regfile_alu_wdata_fw),
      .arb_alu_we_o      (hamsa_alu_we_fw),
      .arb_alu_addr_o    (hamsa_alu_waddr_fw),
      .arb_alu_data_o    (hamsa_alu_wdata_fw),
      .inst2_consumed_o  (hamsa_inst2_consumed),
      .issue2_pending_o  (hamsa_issue2_pending),
      .issue2_blocked_o  (hamsa_issue2_blocked)
  );

  // Keep the second PC and bring-up status visible for waveform/debug builds.
  logic hamsa_unused_status;
  assign hamsa_unused_status = ^hamsa_inst2_pc ^ hamsa_issue2_pending ^
                               hamsa_issue2_blocked;

'''
    text = insert_before_once(
        text,
        "  cv32e40p_load_store_unit #(\n",
        issue_block,
        "Issue-cluster insertion",
    )

    DST.write_text(text)
    print(f"generated {DST.relative_to(ROOT)} ({len(text)} bytes)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # loud failure is intentional for CI
        print(f"gen_hamsa_core.py: ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
