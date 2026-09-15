// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// SPARV full-core instruction-fetch stage built on the HAMSA-DI H2 frontend.
// Adds low-priority next-line prefetching, redundant-request suppression, and
// useful/wasted-prefetch instrumentation while preserving HAMSA replay and the
// CV32E40P architectural redirect semantics.

module cv32e40p_sparv_if_stage #(
    parameter int PULP_XPULP = 0,
    parameter int PULP_SECURE = 0,
    parameter int FPU = 0,
    parameter int L0_LINES = 8,
    parameter bit NATIVE_128_REFILL = 1'b0
) (
    input logic clk,
    input logic rst_n,

    input logic [23:0] m_trap_base_addr_i,
    input logic [23:0] u_trap_base_addr_i,
    input logic [1:0]  trap_addr_mux_i,
    input logic [31:0] boot_addr_i,
    input logic [31:0] dm_exception_addr_i,
    input logic [31:0] dm_halt_addr_i,
    input logic req_i,

    output logic        instr_req_o,
    output logic [31:0] instr_addr_o,
    input  logic        instr_gnt_i,
    input  logic        instr_rvalid_i,
    input  logic [31:0] instr_rdata_i,
    input  logic        instr_err_i,
    input  logic        instr_err_pmp_i,

    output logic         line_req_o,
    output logic [31:0]  line_addr_o,
    input  logic         line_gnt_i,
    input  logic         line_rvalid_i,
    input  logic [127:0] line_rdata_i,

    output logic        instr_valid_id_o,
    output logic [31:0] instr_rdata_id_o,
    output logic        is_compressed_id_o,
    output logic        illegal_c_insn_id_o,
    output logic [31:0] pc_if_o,
    output logic [31:0] pc_id_o,
    output logic        is_fetch_failed_o,

    output logic        inst2_valid_o,
    output logic [31:0] inst2_rdata_o,
    output logic [31:0] inst2_pc_o,
    output logic        inst2_compressed_o,
    output logic        inst2_illegal_c_o,
    input  logic        inst2_consumed_i,

    input logic clear_instr_valid_i,
    input logic pc_set_i,
    input logic [31:0] mepc_i,
    input logic [31:0] uepc_i,
    input logic [31:0] depc_i,
    input logic [3:0] pc_mux_i,
    input logic [2:0] exc_pc_mux_i,
    input logic [4:0] m_exc_vec_pc_mux_i,
    input logic [4:0] u_exc_vec_pc_mux_i,
    output logic csr_mtvec_init_o,

    input logic [31:0] jump_target_id_i,
    input logic [31:0] jump_target_ex_i,
    input logic hwlp_jump_i,
    input logic [31:0] hwlp_target_i,
    input logic halt_if_i,
    input logic id_ready_i,

    output logic if_busy_o,
    output logic perf_imiss_o,
    output logic l0_lookup_o,
    output logic l0_hit_o,
    output logic l0_refill_o,

    output logic sparv_prefetch_candidate_o,
    output logic sparv_prefetch_issued_o,
    output logic sparv_prefetch_fill_o,
    output logic sparv_prefetch_useful_o,
    output logic sparv_prefetch_wasted_o,
    output logic sparv_prefetch_suppressed_o
);

  import cv32e40p_pkg::*;

  logic [23:0] trap_base_addr;
  logic [4:0] exc_vec_pc_mux;
  logic [31:0] exc_pc, redirect_pc;
  logic [31:0] pc_q, lookup_pc;
  logic redirect, invalidate_l0;

  logic lookup_valid, lookup_ready, lookup_hit;
  logic pair_valid, pair_ready;
  logic [31:0] pair_inst1, pair_pc1, pair_inst2, pair_pc2, pair_next_pc;
  logic pair_inst1_c, pair_inst1_illegal;
  logic pair_inst2_valid, pair_inst2_c, pair_inst2_illegal;

  logic demand_miss;
  logic refill_req_valid, refill_req_ready;
  logic [31:0] refill_req_addr;
  logic refill_valid, refill_busy, refill_is_prefetch;
  logic [31:0] refill_addr;
  logic [127:0] refill_data;

  logic prefetch_valid, prefetch_accept, prefetch_cached;
  logic [31:0] prefetch_addr;
  logic prefetch_candidate, prefetch_suppressed;

  always_comb begin
    unique case (trap_addr_mux_i)
      TRAP_MACHINE: trap_base_addr = m_trap_base_addr_i;
      TRAP_USER:    trap_base_addr = u_trap_base_addr_i;
      default:      trap_base_addr = m_trap_base_addr_i;
    endcase
    unique case (trap_addr_mux_i)
      TRAP_MACHINE: exc_vec_pc_mux = m_exc_vec_pc_mux_i;
      TRAP_USER:    exc_vec_pc_mux = u_exc_vec_pc_mux_i;
      default:      exc_vec_pc_mux = m_exc_vec_pc_mux_i;
    endcase
    unique case (exc_pc_mux_i)
      EXC_PC_EXCEPTION: exc_pc = {trap_base_addr, 8'h0};
      EXC_PC_IRQ:       exc_pc = {trap_base_addr, 1'b0, exc_vec_pc_mux, 2'b0};
      EXC_PC_DBD:       exc_pc = {dm_halt_addr_i[31:2], 2'b0};
      EXC_PC_DBE:       exc_pc = {dm_exception_addr_i[31:2], 2'b0};
      default:          exc_pc = {trap_base_addr, 8'h0};
    endcase
  end

  always_comb begin
    redirect_pc = {boot_addr_i[31:2], 2'b0};
    unique case (pc_mux_i)
      PC_BOOT:      redirect_pc = {boot_addr_i[31:2], 2'b0};
      PC_JUMP:      redirect_pc = jump_target_id_i;
      PC_BRANCH:    redirect_pc = jump_target_ex_i;
      PC_EXCEPTION: redirect_pc = exc_pc;
      PC_MRET:      redirect_pc = mepc_i;
      PC_URET:      redirect_pc = uepc_i;
      PC_DRET:      redirect_pc = depc_i;
      PC_FENCEI:    redirect_pc = pc_id_o + 32'd4;
      PC_HWLOOP:    redirect_pc = hwlp_target_i;
      default:      redirect_pc = pc_q;
    endcase
  end

  assign redirect         = pc_set_i || hwlp_jump_i || clear_instr_valid_i;
  assign invalidate_l0    = pc_set_i && (pc_mux_i == PC_FENCEI);
  assign csr_mtvec_init_o = (pc_mux_i == PC_BOOT) && pc_set_i;

  wire [31:0] effective_redirect_pc = pc_set_i ? redirect_pc :
                                       hwlp_jump_i ? hwlp_target_i : pc_q;

  assign pair_ready = id_ready_i && !halt_if_i;

  always_comb begin
    lookup_pc = pc_q;
    if (pair_valid && pair_ready) begin
      if (pair_inst2_valid && !inst2_consumed_i)
        lookup_pc = pair_pc2;
      else
        lookup_pc = pair_next_pc;
    end
  end

  // SPARV permits demand lookups while a speculative refill is in flight. If
  // that lookup misses, the demand waits for the single-outstanding refill
  // engine; if it targets the prefetched line, the completion turns the next
  // lookup into an L0 hit without changing architectural ordering.
  assign lookup_valid = req_i && !halt_if_i && !redirect;

  cv32e40p_hamsa_frontend #(
      .LINES(L0_LINES),
      .FPU  (FPU)
  ) frontend_i (
      .clk(clk), .rst_n(rst_n),
      .invalidate_i(invalidate_l0),
      .redirect_i(redirect), .redirect_pc_i(effective_redirect_pc),
      .lookup_valid_i(lookup_valid), .lookup_pc_i(lookup_pc),
      .lookup_ready_o(lookup_ready), .lookup_hit_o(lookup_hit),
      .refill_valid_i(refill_valid), .refill_addr_i(refill_addr), .refill_data_i(refill_data),
      .pair_valid_o(pair_valid), .pair_ready_i(pair_ready),
      .inst1_o(pair_inst1), .pc1_o(pair_pc1),
      .inst1_compressed_o(pair_inst1_c), .inst1_illegal_c_o(pair_inst1_illegal),
      .inst2_valid_o(pair_inst2_valid), .inst2_o(pair_inst2), .pc2_o(pair_pc2),
      .inst2_compressed_o(pair_inst2_c), .inst2_illegal_c_o(pair_inst2_illegal),
      .next_pc_o(pair_next_pc)
  );

  assign demand_miss = lookup_valid && lookup_ready && !lookup_hit && !refill_valid;

  cv32e40p_sparv_prefetch_ctrl prefetch_ctrl_i (
      .clk(clk), .rst_n(rst_n),
      .redirect_i(redirect), .redirect_pc_i(effective_redirect_pc),
      .demand_lookup_i(lookup_valid && lookup_ready),
      .demand_pc_i(lookup_pc), .demand_hit_i(lookup_hit), .demand_miss_i(demand_miss),
      .demand_refill_i(refill_valid && !refill_is_prefetch),
      .demand_refill_addr_i(refill_addr),
      .refill_busy_i(refill_busy),
      // A candidate already resident in L0 is consumed without a memory request.
      .prefetch_accept_i(prefetch_accept || prefetch_cached),
      .prefetch_valid_o(prefetch_valid), .prefetch_addr_o(prefetch_addr),
      .prefetch_candidate_o(prefetch_candidate),
      .prefetch_suppressed_o(prefetch_suppressed)
  );

  cv32e40p_sparv_prefetch_directory #(.LINES(L0_LINES)) prefetch_dir_i (
      .clk(clk), .rst_n(rst_n), .invalidate_i(invalidate_l0),
      .refill_valid_i(refill_valid), .refill_addr_i(refill_addr),
      .refill_is_prefetch_i(refill_is_prefetch),
      .demand_lookup_i(lookup_valid && lookup_ready),
      .demand_pc_i(lookup_pc), .demand_hit_i(lookup_hit),
      .probe_addr_i(prefetch_addr), .probe_hit_o(prefetch_cached),
      .useful_prefetch_o(sparv_prefetch_useful_o),
      .wasted_prefetch_o(sparv_prefetch_wasted_o)
  );

  cv32e40p_sparv_refill_arbiter refill_arb_i (
      .clk(clk), .rst_n(rst_n), .flush_i(redirect),
      .demand_valid_i(demand_miss), .demand_addr_i(lookup_pc),
      .prefetch_valid_i(prefetch_valid), .prefetch_addr_i(prefetch_addr),
      .prefetch_cached_i(prefetch_cached),
      .refill_req_valid_o(refill_req_valid), .refill_req_addr_o(refill_req_addr),
      .refill_req_ready_i(refill_req_ready), .refill_complete_i(refill_valid),
      .demand_accept_o(), .prefetch_accept_o(prefetch_accept),
      .refill_is_prefetch_o(refill_is_prefetch)
  );

  generate
    if (!NATIVE_128_REFILL) begin : gen_refill32
      cv32e40p_hamsa_refill_32to128 refill_i (
          .clk(clk), .rst_n(rst_n), .flush_i(redirect),
          .miss_valid_i(refill_req_valid), .miss_pc_i(refill_req_addr),
          .miss_ready_o(refill_req_ready),
          .instr_req_o(instr_req_o), .instr_addr_o(instr_addr_o),
          .instr_gnt_i(instr_gnt_i), .instr_rvalid_i(instr_rvalid_i),
          .instr_rdata_i(instr_rdata_i),
          .refill_valid_o(refill_valid), .refill_addr_o(refill_addr),
          .refill_data_o(refill_data), .busy_o(refill_busy)
      );
      assign line_req_o = 1'b0;
      assign line_addr_o = 32'd0;
    end else begin : gen_refill128
      cv32e40p_hamsa_refill_native128 refill_i (
          .clk(clk), .rst_n(rst_n), .flush_i(redirect),
          .miss_valid_i(refill_req_valid), .miss_pc_i(refill_req_addr),
          .miss_ready_o(refill_req_ready),
          .line_req_o(line_req_o), .line_addr_o(line_addr_o),
          .line_gnt_i(line_gnt_i), .line_rvalid_i(line_rvalid_i), .line_rdata_i(line_rdata_i),
          .refill_valid_o(refill_valid), .refill_addr_o(refill_addr),
          .refill_data_o(refill_data), .busy_o(refill_busy)
      );
      assign instr_req_o = 1'b0;
      assign instr_addr_o = 32'd0;
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pc_q <= {boot_addr_i[31:2], 2'b0};
    else if (pc_set_i)
      pc_q <= redirect_pc;
    else if (hwlp_jump_i)
      pc_q <= hwlp_target_i;
    else if (pair_valid && pair_ready) begin
      if (pair_inst2_valid && !inst2_consumed_i)
        pc_q <= pair_pc2;
      else
        pc_q <= pair_next_pc;
    end
  end

  assign instr_valid_id_o    = pair_valid;
  assign instr_rdata_id_o    = pair_inst1;
  assign is_compressed_id_o  = pair_inst1_c;
  assign illegal_c_insn_id_o = pair_inst1_illegal;
  assign pc_id_o             = pair_pc1;
  assign pc_if_o             = pc_q;
  assign is_fetch_failed_o   = 1'b0;

  assign inst2_valid_o       = pair_valid && pair_inst2_valid;
  assign inst2_rdata_o       = pair_inst2;
  assign inst2_pc_o          = pair_pc2;
  assign inst2_compressed_o  = pair_inst2_c;
  assign inst2_illegal_c_o   = pair_inst2_illegal;

  assign if_busy_o    = refill_busy || pair_valid;
  assign perf_imiss_o = demand_miss && refill_req_ready;
  assign l0_lookup_o  = lookup_valid && lookup_ready;
  assign l0_hit_o     = lookup_valid && lookup_ready && lookup_hit;
  assign l0_refill_o  = refill_valid;

  assign sparv_prefetch_candidate_o  = prefetch_candidate;
  assign sparv_prefetch_issued_o     = prefetch_accept;
  assign sparv_prefetch_fill_o       = refill_valid && refill_is_prefetch;
  assign sparv_prefetch_suppressed_o = prefetch_suppressed ||
                                        (prefetch_candidate && prefetch_cached);

  logic unused_err;
  assign unused_err = instr_err_i ^ instr_err_pmp_i ^ (PULP_XPULP != 0) ^
                      (PULP_SECURE != 0);

endmodule
