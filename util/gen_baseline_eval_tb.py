#!/usr/bin/env python3
"""Generate a baseline CV32E40P evaluation testbench without changing B0 RTL.

The generated testbench is identical to example_tb/core/tb_top.sv except that it
counts cycles and architectural retire pulses and emits machine-readable
HAMSA_METRIC lines on every normal termination path. This gives B0 the same log
contract used by HAMSA configurations while keeping CV32e40p-original untouched.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TB = ROOT / "example_tb" / "core"
SRC = TB / "tb_top.sv"
DST = TB / "tb_top_eval.sv"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected one match, found {n}")
    return text.replace(old, new, 1)


def main() -> None:
    top = SRC.read_text()
    top = replace_once(top, "module tb_top #(\n", "module tb_top_eval #(\n", "tb module")
    top = top.replace("endmodule  // tb_top", "endmodule  // tb_top_eval")

    marker = "  // check if we succeded\n"
    block = r'''  // Evaluation-only counters. mhpmevent_minstret is the core's
  // architectural retire event; observing it here does not alter the design.
  longint unsigned eval_cycles_q;
  longint unsigned eval_issue1_retired_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      eval_cycles_q         <= 0;
      eval_issue1_retired_q <= 0;
    end else begin
      eval_cycles_q <= eval_cycles_q + 1;
      if (wrapper_i.wrapper_i.core_i.mhpmevent_minstret)
        eval_issue1_retired_q <= eval_issue1_retired_q + 1;
    end
  end

  task automatic eval_print_metrics;
    begin
      $display("HAMSA_METRIC cycles=%0d issue1_retired=%0d issue2_issued=0 issue2_retired=0 issue2_blocked=0 issue2_killed=0 l0_lookups=0 l0_hits=0",
               eval_cycles_q, eval_issue1_retired_q);
    end
  endtask

'''
    if marker not in top:
        raise RuntimeError("metric insertion anchor not found")
    top = top.replace(marker, block + marker, 1)

    top = top.replace('$display("ALL TESTS PASSED");\n      $finish;',
                      '$display("ALL TESTS PASSED");\n      eval_print_metrics();\n      $finish;')
    top = top.replace('$display("TEST(S) FAILED!");\n      $finish;',
                      '$display("TEST(S) FAILED!");\n      eval_print_metrics();\n      $finish;')
    top = top.replace('if (exit_value == 0) $display("EXIT SUCCESS");\n      else $display("EXIT FAILURE: %d", exit_value);\n      $finish;',
                      'if (exit_value == 0) $display("EXIT SUCCESS");\n      else $display("EXIT FAILURE: %d", exit_value);\n      eval_print_metrics();\n      $finish;')

    DST.write_text(top)
    print(f"generated {DST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
