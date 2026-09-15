#!/usr/bin/env python3
"""Generate simulation-facing HAMSA wrappers without modifying baseline sources.

Use --enable-issue2 0 for H0 and --enable-issue2 1 for H1.
"""

from pathlib import Path
import argparse
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
TB = ROOT / "example_tb" / "core"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected one match, found {n}")
    return text.replace(old, new, 1)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--enable-issue2", choices=["0", "1"], default="1")
    args = p.parse_args()
    issue2_literal = "1'b1" if args.enable_issue2 == "1" else "1'b0"

    subprocess.run(["python3", str(ROOT / "util" / "gen_hamsa_core.py")], check=True)

    wrapper = (RTL / "cv32e40p_wrapper.sv").read_text()
    wrapper = replace_once(wrapper, "module cv32e40p_wrapper #(\n",
                           "module cv32e40p_wrapper_hamsa #(\n", "wrapper module")
    wrapper = replace_once(wrapper, "  cv32e40p_core #(\n",
                           "  cv32e40p_core_hamsa #(\n", "core instance")
    wrapper = replace_once(
        wrapper,
        "      .NUM_MHPMCOUNTERS(NUM_MHPMCOUNTERS)\n  ) core_i (",
        f"      .NUM_MHPMCOUNTERS(NUM_MHPMCOUNTERS),\n"
        f"      .HAMSA_ENABLE_ISSUE2({issue2_literal})\n  ) core_i (",
        "Issue2 configuration",
    )
    (RTL / "cv32e40p_wrapper_hamsa.sv").write_text(wrapper)

    subsystem = (TB / "cv32e40p_tb_subsystem.sv").read_text()
    subsystem = replace_once(subsystem, "module cv32e40p_tb_subsystem #(\n",
                             "module cv32e40p_tb_subsystem_hamsa #(\n", "subsystem module")
    subsystem = replace_once(subsystem, "  cv32e40p_wrapper #(\n",
                             "  cv32e40p_wrapper_hamsa #(\n", "subsystem wrapper")
    subsystem = subsystem.replace("endmodule  // cv32e40p_tb_subsystem",
                                  "endmodule  // cv32e40p_tb_subsystem_hamsa")
    (TB / "cv32e40p_tb_subsystem_hamsa.sv").write_text(subsystem)

    top = (TB / "tb_top.sv").read_text()
    top = replace_once(top, "module tb_top #(\n", "module tb_top_hamsa #(\n", "tb module")
    top = replace_once(top, "  cv32e40p_tb_subsystem #(\n",
                       "  cv32e40p_tb_subsystem_hamsa #(\n", "tb subsystem")
    top = top.replace("endmodule  // tb_top", "endmodule  // tb_top_hamsa")

    marker = "  // check if we succeded\n"
    counter_block = r'''  // HAMSA benchmark-observability counters.
  longint unsigned hamsa_cycles_q;
  longint unsigned hamsa_issue1_retired_q;
  longint unsigned hamsa_issue2_issued_q;
  longint unsigned hamsa_issue2_retired_q;
  longint unsigned hamsa_issue2_blocked_q;
  longint unsigned hamsa_issue2_killed_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      hamsa_cycles_q         <= 0;
      hamsa_issue1_retired_q <= 0;
      hamsa_issue2_issued_q  <= 0;
      hamsa_issue2_retired_q <= 0;
      hamsa_issue2_blocked_q <= 0;
      hamsa_issue2_killed_q  <= 0;
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
    end
  end

  task automatic hamsa_print_metrics;
    begin
      $display("HAMSA_METRIC cycles=%0d issue1_retired=%0d issue2_issued=%0d issue2_retired=%0d issue2_blocked=%0d issue2_killed=%0d l0_lookups=0 l0_hits=0",
               hamsa_cycles_q, hamsa_issue1_retired_q, hamsa_issue2_issued_q,
               hamsa_issue2_retired_q, hamsa_issue2_blocked_q,
               hamsa_issue2_killed_q);
    end
  endtask

'''
    if marker not in top:
        raise RuntimeError("tb metric insertion anchor not found")
    top = top.replace(marker, counter_block + marker, 1)
    top = top.replace('$display("ALL TESTS PASSED");\n      $finish;',
                      '$display("ALL TESTS PASSED");\n      hamsa_print_metrics();\n      $finish;')
    top = top.replace('$display("TEST(S) FAILED!");\n      $finish;',
                      '$display("TEST(S) FAILED!");\n      hamsa_print_metrics();\n      $finish;')
    top = top.replace('if (exit_value == 0) $display("EXIT SUCCESS");\n      else $display("EXIT FAILURE: %d", exit_value);\n      $finish;',
                      'if (exit_value == 0) $display("EXIT SUCCESS");\n      else $display("EXIT FAILURE: %d", exit_value);\n      hamsa_print_metrics();\n      $finish;')
    (TB / "tb_top_hamsa.sv").write_text(top)

    manifest = (ROOT / "cv32e40p_manifest.flist").read_text()
    manifest = replace_once(manifest,
                            "${DESIGN_RTL_DIR}/cv32e40p_core.sv\n",
                            "${DESIGN_RTL_DIR}/cv32e40p_core_hamsa.sv\n",
                            "manifest core")
    manifest = replace_once(manifest,
                            "${DESIGN_RTL_DIR}/cv32e40p_wrapper.sv\n",
                            "${DESIGN_RTL_DIR}/cv32e40p_wrapper_hamsa.sv\n",
                            "manifest wrapper")
    (ROOT / "cv32e40p_manifest_hamsa.flist").write_text(manifest)

    mode = "H1" if args.enable_issue2 == "1" else "H0"
    print(f"generated HAMSA simulation wrapper/testbench/manifest for {mode}")


if __name__ == "__main__":
    main()
