#!/usr/bin/env python3
"""Generate executable H2-32 or H2-128 simulation wrappers.

H2-32 uses cv32e40p_hamsa_if_stage with the legacy 32-bit instruction port and
four-beat 128-bit L0 refills. H2-128 uses the same core/frontend but connects the
native 128-bit line port directly to example_tb's mm_ram configured for a
128-bit instruction read. The legacy instruction port remains 32 bits in both
modes; in H2-128 it is simply tied idle. This avoids conflating bus-width
parameters in the wrapper with the independent native line channel.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
TB = ROOT / "example_tb" / "core"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected one match, found {n}")
    return text.replace(old, new, 1)


def inject_metrics(top: str) -> str:
    marker = "  // check if we succeded\n"
    block = r'''  // HAMSA H2 benchmark observability.
  longint unsigned hamsa_cycles_q;
  longint unsigned hamsa_issue1_retired_q;
  longint unsigned hamsa_issue2_issued_q;
  longint unsigned hamsa_issue2_retired_q;
  longint unsigned hamsa_issue2_blocked_q;
  longint unsigned hamsa_issue2_killed_q;
  longint unsigned hamsa_block_raw_q;
  longint unsigned hamsa_block_waw_q;
  longint unsigned hamsa_block_unsupported_q;
  longint unsigned hamsa_block_serializing_q;
  longint unsigned hamsa_block_busy_q;
  longint unsigned hamsa_block_decode_q;
  longint unsigned hamsa_l0_lookups_q;
  longint unsigned hamsa_l0_hits_q;
  longint unsigned hamsa_l0_refills_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      hamsa_cycles_q             <= 0;
      hamsa_issue1_retired_q     <= 0;
      hamsa_issue2_issued_q      <= 0;
      hamsa_issue2_retired_q     <= 0;
      hamsa_issue2_blocked_q     <= 0;
      hamsa_issue2_killed_q      <= 0;
      hamsa_block_raw_q          <= 0;
      hamsa_block_waw_q          <= 0;
      hamsa_block_unsupported_q  <= 0;
      hamsa_block_serializing_q  <= 0;
      hamsa_block_busy_q         <= 0;
      hamsa_block_decode_q       <= 0;
      hamsa_l0_lookups_q         <= 0;
      hamsa_l0_hits_q            <= 0;
      hamsa_l0_refills_q         <= 0;
    end else begin
      hamsa_cycles_q <= hamsa_cycles_q + 1;
      if (wrapper_i.wrapper_i.core_i.mhpmevent_minstret)
        hamsa_issue1_retired_q <= hamsa_issue1_retired_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_inst2_consumed)
        hamsa_issue2_issued_q <= hamsa_issue2_issued_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_issue2_retired)
        hamsa_issue2_retired_q <= hamsa_issue2_retired_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_issue2_blocked)
        hamsa_issue2_blocked_q <= hamsa_issue2_blocked_q + 1;
      if (wrapper_i.wrapper_i.core_i.pc_set &&
          wrapper_i.wrapper_i.core_i.hamsa_issue2_pending)
        hamsa_issue2_killed_q <= hamsa_issue2_killed_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_issue2_block_raw)
        hamsa_block_raw_q <= hamsa_block_raw_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_issue2_block_waw)
        hamsa_block_waw_q <= hamsa_block_waw_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_issue2_block_unsupported)
        hamsa_block_unsupported_q <= hamsa_block_unsupported_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_issue2_block_serializing)
        hamsa_block_serializing_q <= hamsa_block_serializing_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_issue2_block_busy)
        hamsa_block_busy_q <= hamsa_block_busy_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_issue2_block_decode)
        hamsa_block_decode_q <= hamsa_block_decode_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_l0_lookup)
        hamsa_l0_lookups_q <= hamsa_l0_lookups_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_l0_hit)
        hamsa_l0_hits_q <= hamsa_l0_hits_q + 1;
      if (wrapper_i.wrapper_i.core_i.hamsa_l0_refill)
        hamsa_l0_refills_q <= hamsa_l0_refills_q + 1;
    end
  end

  task automatic hamsa_print_metrics;
    begin
      $display("HAMSA_METRIC cycles=%0d issue1_retired=%0d issue2_issued=%0d issue2_retired=%0d issue2_blocked=%0d issue2_killed=%0d l0_lookups=%0d l0_hits=%0d l0_refills=%0d block_raw=%0d block_waw=%0d block_unsupported=%0d block_serializing=%0d block_busy=%0d block_decode=%0d",
               hamsa_cycles_q, hamsa_issue1_retired_q, hamsa_issue2_issued_q,
               hamsa_issue2_retired_q, hamsa_issue2_blocked_q,
               hamsa_issue2_killed_q, hamsa_l0_lookups_q, hamsa_l0_hits_q,
               hamsa_l0_refills_q, hamsa_block_raw_q, hamsa_block_waw_q,
               hamsa_block_unsupported_q, hamsa_block_serializing_q,
               hamsa_block_busy_q, hamsa_block_decode_q);
    end
  endtask

'''
    if marker not in top:
        raise RuntimeError("metric insertion anchor not found")
    top = top.replace(marker, block + marker, 1)
    top = top.replace('$display("ALL TESTS PASSED");\n      $finish;',
                      '$display("ALL TESTS PASSED");\n      hamsa_print_metrics();\n      $finish;')
    top = top.replace('$display("TEST(S) FAILED!");\n      $finish;',
                      '$display("TEST(S) FAILED!");\n      hamsa_print_metrics();\n      $finish;')
    top = top.replace('if (exit_value == 0) $display("EXIT SUCCESS");\n      else $display("EXIT FAILURE: %d", exit_value);\n      $finish;',
                      'if (exit_value == 0) $display("EXIT SUCCESS");\n      else $display("EXIT FAILURE: %d", exit_value);\n      hamsa_print_metrics();\n      $finish;')
    return top


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--native", type=int, choices=[0, 1], default=0)
    args = ap.parse_args()
    native = bool(args.native)
    suffix = "h2_128" if native else "h2_32"

    subprocess.run(["python3", str(ROOT / "util" / "gen_hamsa_core_h2.py")],
                   cwd=ROOT, check=True)

    # ------------------------------------------------------------------
    # Wrapper
    # ------------------------------------------------------------------
    wrapper = (RTL / "cv32e40p_wrapper.sv").read_text()
    wrapper_mod = f"cv32e40p_wrapper_{suffix}"
    wrapper = replace_once(wrapper, "module cv32e40p_wrapper #(",
                           f"module {wrapper_mod} #(", "wrapper module")
    wrapper = replace_once(wrapper, "  cv32e40p_core #(\n",
                           "  cv32e40p_core_hamsa_h2 #(\n", "core instance")
    wrapper = replace_once(
        wrapper,
        "      .NUM_MHPMCOUNTERS(NUM_MHPMCOUNTERS)\n",
        "      .NUM_MHPMCOUNTERS(NUM_MHPMCOUNTERS),\n"
        "      .HAMSA_ENABLE_ISSUE2(1'b1),\n"
        f"      .HAMSA_NATIVE_128_REFILL(1'b{1 if native else 0}),\n"
        "      .HAMSA_L0_LINES(8)\n",
        "H2 core parameters",
    )

    if native:
        port_anchor = """    output logic [31:0] instr_addr_o,\n    input  logic [31:0] instr_rdata_i,\n\n"""
        line_ports = port_anchor + """    output logic         hamsa_line_req_o,\n    output logic [31:0]  hamsa_line_addr_o,\n    input  logic         hamsa_line_gnt_i,\n    input  logic         hamsa_line_rvalid_i,\n    input  logic [127:0] hamsa_line_rdata_i,\n\n"""
        wrapper = replace_once(wrapper, port_anchor, line_ports, "wrapper line ports")
        core_instr_anchor = """      .instr_addr_o  (instr_addr_o),\n      .instr_rdata_i (instr_rdata_i),\n\n"""
        core_line = core_instr_anchor + """      .hamsa_line_req_o    (hamsa_line_req_o),\n      .hamsa_line_addr_o   (hamsa_line_addr_o),\n      .hamsa_line_gnt_i    (hamsa_line_gnt_i),\n      .hamsa_line_rvalid_i (hamsa_line_rvalid_i),\n      .hamsa_line_rdata_i  (hamsa_line_rdata_i),\n\n"""
        wrapper = replace_once(wrapper, core_instr_anchor, core_line, "core line ports")
    else:
        core_instr_anchor = """      .instr_addr_o  (instr_addr_o),\n      .instr_rdata_i (instr_rdata_i),\n\n"""
        tied = core_instr_anchor + """      .hamsa_line_req_o    (),\n      .hamsa_line_addr_o   (),\n      .hamsa_line_gnt_i    (1'b0),\n      .hamsa_line_rvalid_i (1'b0),\n      .hamsa_line_rdata_i  (128'd0),\n\n"""
        wrapper = replace_once(wrapper, core_instr_anchor, tied, "tie native ports")

    (RTL / f"cv32e40p_wrapper_{suffix}.sv").write_text(wrapper)

    # ------------------------------------------------------------------
    # Testbench subsystem
    # ------------------------------------------------------------------
    subsystem = (TB / "cv32e40p_tb_subsystem.sv").read_text()
    sub_mod = f"cv32e40p_tb_subsystem_{suffix}"
    subsystem = replace_once(subsystem, "module cv32e40p_tb_subsystem #(\n",
                             f"module {sub_mod} #(\n", "subsystem module")
    subsystem = replace_once(subsystem, "  cv32e40p_wrapper #(\n",
                             f"  {wrapper_mod} #(\n", "subsystem wrapper")
    subsystem = subsystem.replace("endmodule  // cv32e40p_tb_subsystem",
                                  f"endmodule  // {sub_mod}")

    if native:
        decl_anchor = """  logic [INSTR_RDATA_WIDTH-1:0]       instr_rdata;\n\n"""
        decl_new = decl_anchor + """  logic                               hamsa_line_req;\n  logic                               hamsa_line_gnt;\n  logic                               hamsa_line_rvalid;\n  logic [                 31:0]       hamsa_line_addr;\n  logic [                127:0]       hamsa_line_rdata;\n\n"""
        subsystem = replace_once(subsystem, decl_anchor, decl_new, "line signal declarations")

        wrap_instr_anchor = """      .instr_gnt_i   (instr_gnt),\n      .instr_rvalid_i(instr_rvalid),\n\n"""
        wrap_line = wrap_instr_anchor + """      .hamsa_line_req_o    (hamsa_line_req),\n      .hamsa_line_addr_o   (hamsa_line_addr),\n      .hamsa_line_gnt_i    (hamsa_line_gnt),\n      .hamsa_line_rvalid_i (hamsa_line_rvalid),\n      .hamsa_line_rdata_i  (hamsa_line_rdata),\n\n"""
        subsystem = replace_once(subsystem, wrap_instr_anchor, wrap_line, "wrapper line connections")

        subsystem = subsystem.replace("\n\n  generate\n", "\n\n  assign instr_gnt = 1'b0;\n  assign instr_rvalid = 1'b0;\n  assign instr_rdata = '0;\n\n  generate\n", 1)

        ram_param = """  mm_ram #(\n      .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),\n      .INSTR_RDATA_WIDTH(INSTR_RDATA_WIDTH)\n"""
        ram_param_new = """  mm_ram #(\n      .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),\n      .INSTR_RDATA_WIDTH(128)\n"""
        subsystem = replace_once(subsystem, ram_param, ram_param_new, "native RAM width")
        ram_instr = """      .instr_req_i   (instr_req),\n      .instr_addr_i  (instr_addr[RAM_ADDR_WIDTH-1:0]),\n      .instr_rdata_o (instr_rdata),\n      .instr_rvalid_o(instr_rvalid),\n      .instr_gnt_o   (instr_gnt),\n"""
        ram_line = """      .instr_req_i   (hamsa_line_req),\n      .instr_addr_i  (hamsa_line_addr[RAM_ADDR_WIDTH-1:0]),\n      .instr_rdata_o (hamsa_line_rdata),\n      .instr_rvalid_o(hamsa_line_rvalid),\n      .instr_gnt_o   (hamsa_line_gnt),\n"""
        subsystem = replace_once(subsystem, ram_instr, ram_line, "native RAM line interface")

    (TB / f"cv32e40p_tb_subsystem_{suffix}.sv").write_text(subsystem)

    # ------------------------------------------------------------------
    # Testbench top + counters. Keep INSTR_RDATA_WIDTH at 32 in both modes;
    # H2-128's independent native line path is explicitly 128 bits in subsystem.
    # ------------------------------------------------------------------
    top = (TB / "tb_top.sv").read_text()
    top_mod = f"tb_top_{suffix}"
    top = replace_once(top, "module tb_top #(\n", f"module {top_mod} #(\n", "top module")
    top = replace_once(top, "  cv32e40p_tb_subsystem #(\n",
                       f"  {sub_mod} #(\n", "top subsystem")
    top = top.replace("endmodule  // tb_top", f"endmodule  // {top_mod}")
    top = top.replace("$dumpvars(0, tb_top);", f"$dumpvars(0, {top_mod});")
    top = inject_metrics(top)
    (TB / f"tb_top_{suffix}.sv").write_text(top)

    # ------------------------------------------------------------------
    # Manifest
    # ------------------------------------------------------------------
    manifest = (ROOT / "cv32e40p_manifest.flist").read_text()
    manifest = replace_once(manifest,
                            "${DESIGN_RTL_DIR}/cv32e40p_core.sv\n",
                            "${DESIGN_RTL_DIR}/cv32e40p_core_hamsa_h2.sv\n",
                            "manifest core")
    manifest = replace_once(manifest,
                            "${DESIGN_RTL_DIR}/cv32e40p_wrapper.sv\n",
                            f"${{DESIGN_RTL_DIR}}/cv32e40p_wrapper_{suffix}.sv\n",
                            "manifest wrapper")
    (ROOT / f"cv32e40p_manifest_{suffix}.flist").write_text(manifest)

    print(f"generated executable {suffix} simulation files")


if __name__ == "__main__":
    main()
