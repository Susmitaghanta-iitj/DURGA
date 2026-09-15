#!/usr/bin/env python3
"""Generate executable SPARV-32 or SPARV-128 example-testbench variants.

The script reuses the verified HAMSA H2 simulation wiring, then swaps in the
SPARV core and adds SPARV-specific runtime counters. This keeps the memory,
stdout/exit, interrupt, and testbench behavior identical to HAMSA H2 while
making the SPARV prefetch + accelerated multiplier path executable.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
TB = ROOT / "example_tb" / "core"

SPARV_SOURCES = """${DESIGN_RTL_DIR}/cv32e40p_sparv_prefetch_ctrl.sv
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


def replace_required(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f"{label}: anchor not found: {old!r}")
    return text.replace(old, new)


def inject_sparv_metrics(top: str) -> str:
    marker = "  // check if we succeded\n"
    if marker not in top:
        raise RuntimeError("SPARV metric insertion anchor missing")
    block = r'''  // SPARV benchmark observability. Hierarchical references are
  // testbench-only and do not affect synthesizable core RTL.
  longint unsigned sparv_prefetch_candidates_q;
  longint unsigned sparv_prefetch_issued_q;
  longint unsigned sparv_prefetch_fills_q;
  longint unsigned sparv_prefetch_useful_q;
  longint unsigned sparv_prefetch_wasted_q;
  longint unsigned sparv_prefetch_suppressed_q;
  longint unsigned sparv_demand_misses_q;
  longint unsigned sparv_tcim_requests_q;
  longint unsigned sparv_mac8_ops_q;
  longint unsigned sparv_mac16_ops_q;
  longint unsigned sparv_mac32_ops_q;
  longint unsigned sparv_stall_cycles_q;

  wire sparv_accel_start = wrapper_i.wrapper_i.core_i.ex_stage_i.mult_i.enable_i &&
                           wrapper_i.wrapper_i.core_i.ex_stage_i.mult_i.accel_select &&
                           wrapper_i.wrapper_i.core_i.ex_stage_i.mult_i.accel_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sparv_prefetch_candidates_q <= 0;
      sparv_prefetch_issued_q <= 0;
      sparv_prefetch_fills_q <= 0;
      sparv_prefetch_useful_q <= 0;
      sparv_prefetch_wasted_q <= 0;
      sparv_prefetch_suppressed_q <= 0;
      sparv_demand_misses_q <= 0;
      sparv_tcim_requests_q <= 0;
      sparv_mac8_ops_q <= 0;
      sparv_mac16_ops_q <= 0;
      sparv_mac32_ops_q <= 0;
      sparv_stall_cycles_q <= 0;
    end else begin
      if (wrapper_i.wrapper_i.core_i.if_stage_i.sparv_prefetch_candidate_o)
        sparv_prefetch_candidates_q <= sparv_prefetch_candidates_q + 1;
      if (wrapper_i.wrapper_i.core_i.if_stage_i.sparv_prefetch_issued_o)
        sparv_prefetch_issued_q <= sparv_prefetch_issued_q + 1;
      if (wrapper_i.wrapper_i.core_i.if_stage_i.sparv_prefetch_fill_o)
        sparv_prefetch_fills_q <= sparv_prefetch_fills_q + 1;
      if (wrapper_i.wrapper_i.core_i.if_stage_i.sparv_prefetch_useful_o)
        sparv_prefetch_useful_q <= sparv_prefetch_useful_q + 1;
      if (wrapper_i.wrapper_i.core_i.if_stage_i.sparv_prefetch_wasted_o)
        sparv_prefetch_wasted_q <= sparv_prefetch_wasted_q + 1;
      if (wrapper_i.wrapper_i.core_i.if_stage_i.sparv_prefetch_suppressed_o)
        sparv_prefetch_suppressed_q <= sparv_prefetch_suppressed_q + 1;
      if (wrapper_i.wrapper_i.core_i.if_stage_i.demand_miss)
        sparv_demand_misses_q <= sparv_demand_misses_q + 1;
      if ((wrapper_i.wrapper_i.core_i.if_stage_i.instr_req_o &&
           wrapper_i.wrapper_i.core_i.if_stage_i.instr_gnt_i) ||
          (wrapper_i.wrapper_i.core_i.if_stage_i.line_req_o &&
           wrapper_i.wrapper_i.core_i.if_stage_i.line_gnt_i))
        sparv_tcim_requests_q <= sparv_tcim_requests_q + 1;
      if (sparv_accel_start) begin
        case (wrapper_i.wrapper_i.core_i.ex_stage_i.mult_i.accel_mode)
          2'b00: sparv_mac8_ops_q <= sparv_mac8_ops_q + 1;
          2'b01: sparv_mac16_ops_q <= sparv_mac16_ops_q + 1;
          2'b10: sparv_mac32_ops_q <= sparv_mac32_ops_q + 1;
          default: ;
        endcase
      end
      if (wrapper_i.wrapper_i.core_i.ex_stage_i.mult_i.accel_busy &&
          !wrapper_i.wrapper_i.core_i.ex_stage_i.mult_i.accel_result_valid)
        sparv_stall_cycles_q <= sparv_stall_cycles_q + 1;
    end
  end

  task automatic sparv_print_metrics;
    longint unsigned total_retired;
    begin
      total_retired = hamsa_issue1_retired_q + hamsa_issue2_retired_q;
      $display("SPARV_METRIC cycles=%0d retired=%0d dual_pairs=%0d l0_lookups=%0d l0_hits=%0d demand_misses=%0d prefetch_candidates=%0d prefetch_issued=%0d prefetch_fills=%0d prefetch_useful=%0d prefetch_wasted=%0d prefetch_suppressed=%0d tcim_requests=%0d mac8_ops=%0d mac16_ops=%0d mac32_ops=%0d sparv_stall_cycles=%0d",
               hamsa_cycles_q, total_retired, hamsa_issue2_retired_q,
               hamsa_l0_lookups_q, hamsa_l0_hits_q, sparv_demand_misses_q,
               sparv_prefetch_candidates_q, sparv_prefetch_issued_q,
               sparv_prefetch_fills_q, sparv_prefetch_useful_q,
               sparv_prefetch_wasted_q, sparv_prefetch_suppressed_q,
               sparv_tcim_requests_q, sparv_mac8_ops_q, sparv_mac16_ops_q,
               sparv_mac32_ops_q, sparv_stall_cycles_q);
    end
  endtask

'''
    top = top.replace(marker, block + marker, 1)
    top = top.replace("      hamsa_print_metrics();\n      $finish;",
                      "      hamsa_print_metrics();\n      sparv_print_metrics();\n      $finish;")
    return top


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--native", type=int, choices=[0, 1], default=0)
    args = ap.parse_args()
    native = bool(args.native)
    hsuffix = "h2_128" if native else "h2_32"
    ssuffix = "sparv_128" if native else "sparv_32"

    subprocess.run(["python3", str(ROOT / "util" / "gen_hamsa_sim_h2.py"),
                    "--native", str(int(native))], cwd=ROOT, check=True)
    subprocess.run(["python3", str(ROOT / "util" / "gen_sparv_core.py")],
                   cwd=ROOT, check=True)

    # Wrapper: retain the H2 I/O shell, swap the core implementation.
    hwrap = f"cv32e40p_wrapper_{hsuffix}"
    swrap = f"cv32e40p_wrapper_{ssuffix}"
    wrapper = (RTL / f"{hwrap}.sv").read_text()
    wrapper = replace_required(wrapper, hwrap, swrap, "wrapper rename")
    wrapper = replace_required(wrapper, "cv32e40p_core_hamsa_h2",
                               "cv32e40p_core_sparv", "SPARV core swap")
    (RTL / f"{swrap}.sv").write_text(wrapper)

    # Subsystem.
    hsub = f"cv32e40p_tb_subsystem_{hsuffix}"
    ssub = f"cv32e40p_tb_subsystem_{ssuffix}"
    subsystem = (TB / f"{hsub}.sv").read_text()
    subsystem = replace_required(subsystem, hsub, ssub, "subsystem rename")
    subsystem = replace_required(subsystem, hwrap, swrap, "subsystem wrapper swap")
    (TB / f"{ssub}.sv").write_text(subsystem)

    # Top: preserve HAMSA metrics and append SPARV-specific counters.
    htop = f"tb_top_{hsuffix}"
    stop = f"tb_top_{ssuffix}"
    top = (TB / f"{htop}.sv").read_text()
    top = replace_required(top, htop, stop, "top rename")
    top = replace_required(top, hsub, ssub, "top subsystem swap")
    top = inject_sparv_metrics(top)
    (TB / f"{stop}.sv").write_text(top)

    # Start from the proven H2 manifest and add SPARV implementation sources.
    hmanifest_path = ROOT / f"cv32e40p_manifest_{hsuffix}.flist"
    manifest = hmanifest_path.read_text()
    manifest = replace_required(manifest,
        "${DESIGN_RTL_DIR}/cv32e40p_core_hamsa_h2.sv",
        "${DESIGN_RTL_DIR}/cv32e40p_core_sparv.sv", "manifest core")
    manifest = replace_required(manifest,
        f"${{DESIGN_RTL_DIR}}/{hwrap}.sv",
        f"${{DESIGN_RTL_DIR}}/{swrap}.sv", "manifest wrapper")
    anchor = "${DESIGN_RTL_DIR}/cv32e40p_hamsa_if_stage.sv\n"
    if SPARV_SOURCES.splitlines()[0] not in manifest:
        if anchor not in manifest:
            raise RuntimeError("SPARV source insertion anchor missing")
        manifest = manifest.replace(anchor, anchor + SPARV_SOURCES, 1)
    out_manifest = ROOT / f"cv32e40p_manifest_{ssuffix}.flist"
    out_manifest.write_text(manifest)

    print(f"generated rtl/{swrap}.sv")
    print(f"generated example_tb/core/{ssub}.sv")
    print(f"generated example_tb/core/{stop}.sv")
    print(f"generated {out_manifest.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
