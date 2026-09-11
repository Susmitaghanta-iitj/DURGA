// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// HAMSA-DI full-core instruction-fetch stage.
//
// This module preserves the CV32E40P architectural PC redirect semantics
// (boot/jump/branch/trap/mret/uret/dret/fence.i/hardware-loop) while replacing
// the original word-oriented prefetch/align/decompress path with the HAMSA
// 8x128-bit L0 + RV32C-aware dual extractor. It can refill the L0 either over
// the legacy 32-bit instruction bus (four beats per line, H2-32) or through a
// native 128-bit line interface (one beat per line, H2-128).
//
// Important replay rule: if Inst2 cannot be consumed by the secondary lane,
// the next lookup PC becomes pc2 so the younger instruction is re-presented as
// Issue1. Therefore dual issue is an optimization only; architectural progress
// remains strictly in order.

module cv32e40p_hamsa_if_stage #(
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
    input logic [ 1:0] trap_addr_mux_i,
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
    output logic l0_refill_o
);

  import cv32e40p_pkg::*;

  logic [23:0] trap_base_addr;
  logic [4:0]  exc_vec_pc_mux;
  logic [31:0] exc_pc;
  logic [31:0] redirect_pc;

  logic [31:0] pc_q;
  logic [31:0] lookup_pc;
  logic        redirect;
  logic        invalidate_l0;

  logic lookup_valid;
  logic lookup_ready;
  logic lookup_hit;
  logic pair_valid;
  logic pair_ready;
  logic [31:0] pair_inst1;
  logic [31:0] pair_pc1;
  logic pair_inst1_c;
  logic pair_inst1_illegal;
  logic pair_inst2_valid;
  logic [31:0] pair_inst2;
  logic [31:0] pair_pc2;
  logic pair_inst2_c;
  logic pair_inst2_illegal;
  logic [31:0] pair_next_pc;

  logic miss_valid;
  logic miss_ready;
  logic refill_valid;
  logic [31:0] refill_addr;
  logic [127:0] refill_data;
  logic refill_busy;

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

  assign redirect          = pc_set_i || hwlp_jump_i || clear_instr_valid_i;
  assign invalidate_l0     = pc_set_i && (pc_mux_i == PC_FENCEI);
  assign csr_mtvec_init_o  = (pc_mux_i == PC_BOOT) && pc_set_i;

  wire [31:0] effective_redirect_pc = pc_set_i ? redirect_pc :
                                       hwlp_jump_i ? hwlp_target_i : pc_q;

  assign pair_ready = id_ready_i && !halt_if_i;

  // Look one pair ahead when the current pair is retiring. This avoids a
  // compulsory bubble on L0 hits while remaining replay-correct: if Inst2 was
  // not accepted, pc2 is looked up and becomes the next primary instruction.
  always_comb begin
    lookup_pc = pc_q;
    if (pair_valid && pair_ready) begin
      if (pair_inst2_valid && !inst2_consumed_i)
        lookup_pc = pair_pc2;
      else
        lookup_pc = pair_next_pc;
    end
  end

  assign lookup_valid = req_i && !halt_if_i && !refill_busy && !redirect;

  cv32e40p_hamsa_frontend #(
      .LINES(L0_LINES),
      .FPU  (FPU)
  ) frontend_i (
      .clk                (clk),
      .rst_n              (rst_n),
      .invalidate_i       (invalidate_l0),
      .redirect_i         (redirect),
      .redirect_pc_i      (effective_redirect_pc),
      .lookup_valid_i     (lookup_valid),
      .lookup_pc_i        (lookup_pc),
      .lookup_ready_o     (lookup_ready),
      .lookup_hit_o       (lookup_hit),
      .refill_valid_i     (refill_valid),
      .refill_addr_i      (refill_addr),
      .refill_data_i      (refill_data),
      .pair_valid_o       (pair_valid),
      .pair_ready_i       (pair_ready),
      .inst1_o            (pair_inst1),
      .pc1_o              (pair_pc1),
      .inst1_compressed_o (pair_inst1_c),
      .inst1_illegal_c_o  (pair_inst1_illegal),
      .inst2_valid_o      (pair_inst2_valid),
      .inst2_o            (pair_inst2),
      .pc2_o              (pair_pc2),
      .inst2_compressed_o (pair_inst2_c),
      .inst2_illegal_c_o  (pair_inst2_illegal),
      .next_pc_o          (pair_next_pc)
  );

  assign miss_valid = lookup_valid && lookup_ready && !lookup_hit;

  generate
    if (!NATIVE_128_REFILL) begin : gen_refill32
      cv32e40p_hamsa_refill_32to128 refill_i (
          .clk            (clk),
          .rst_n          (rst_n),
          .flush_i        (redirect),
          .miss_valid_i   (miss_valid),
          .miss_pc_i      (lookup_pc),
          .miss_ready_o   (miss_ready),
          .instr_req_o    (instr_req_o),
          .instr_addr_o   (instr_addr_o),
          .instr_gnt_i    (instr_gnt_i),
          .instr_rvalid_i (instr_rvalid_i),
          .instr_rdata_i  (instr_rdata_i),
          .refill_valid_o (refill_valid),
          .refill_addr_o  (refill_addr),
          .refill_data_o  (refill_data),
          .busy_o         (refill_busy)
      );
      assign line_req_o  = 1'b0;
      assign line_addr_o = 32'd0;
    end else begin : gen_refill128
      cv32e40p_hamsa_refill_native128 refill_i (
          .clk            (clk),
          .rst_n          (rst_n),
          .flush_i        (redirect),
          .miss_valid_i   (miss_valid),
          .miss_pc_i      (lookup_pc),
          .miss_ready_o   (miss_ready),
          .line_req_o     (line_req_o),
          .line_addr_o    (line_addr_o),
          .line_gnt_i     (line_gnt_i),
          .line_rvalid_i  (line_rvalid_i),
          .line_rdata_i   (line_rdata_i),
          .refill_valid_o (refill_valid),
          .refill_addr_o  (refill_addr),
          .refill_data_o  (refill_data),
          .busy_o         (refill_busy)
      );
      assign instr_req_o  = 1'b0;
      assign instr_addr_o = 32'd0;
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q <= {boot_addr_i[31:2], 2'b0};
    end else begin
      if (pc_set_i)
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
  assign perf_imiss_o = miss_valid && miss_ready;
  assign l0_lookup_o  = lookup_valid && lookup_ready;
  assign l0_hit_o     = lookup_valid && lookup_ready && lookup_hit;
  assign l0_refill_o  = refill_valid;

  logic unused_err;
  assign unused_err = instr_err_i ^ instr_err_pmp_i ^ (PULP_XPULP != 0) ^
                      (PULP_SECURE != 0);

endmodule
