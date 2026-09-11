// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Integration top for the HAMSA-DI prototype blocks. The original CV32E40P
// primary lane remains an external/full-featured pipeline. This module provides
// the 128-bit L0 frontend, pair delivery, recovery/kill, secondary issue lane,
// forwarding, and write-port arbitration around that primary lane.

module cv32e40p_hamsa_dual_issue_top #(
    parameter int L0_LINES = 8,
    parameter int FPU      = 0
) (
    input logic clk,
    input logic rst_n,

    input  logic         lookup_valid_i,
    input  logic [31:0]  lookup_pc_i,
    output logic         lookup_ready_o,
    output logic         lookup_hit_o,
    input  logic         refill_valid_i,
    input  logic [31:0]  refill_addr_i,
    input  logic [127:0] refill_data_i,
    input  logic         invalidate_l0_i,

    input logic        branch_in_ex_i,
    input logic        branch_taken_i,
    input logic        jump_redirect_i,
    input logic        exception_redirect_i,
    input logic        debug_redirect_i,
    input logic [31:0] redirect_pc_i,

    output logic        issue1_valid_o,
    output logic [31:0] issue1_instr_o,
    output logic [31:0] issue1_pc_o,
    output logic        issue1_compressed_o,
    output logic        issue1_illegal_c_o,
    input  logic        issue1_ready_i,

    input logic        primary_commit_safe_i,
    input logic        primary_wb_we_i,
    input logic [5:0]  primary_wb_addr_i,
    input logic [31:0] primary_wb_data_i,
    input logic        primary_alu_we_i,
    input logic [5:0]  primary_alu_addr_i,
    input logic [31:0] primary_alu_data_i,
    input logic        primary_ex_we_i,
    input logic [5:0]  primary_ex_addr_i,
    input logic [31:0] primary_ex_data_i,

    output logic        arb_alu_we_o,
    output logic [5:0]  arb_alu_addr_o,
    output logic [31:0] arb_alu_data_o,

    output logic [31:0] next_pc_o,
    output logic        issue2_issued_o,
    output logic        issue2_retired_o,
    output logic        issue2_killed_o,
    output logic        issue2_pending_o,
    output logic        issue2_blocked_o,
    output logic        issue2_block_raw_o,
    output logic        issue2_block_waw_o,
    output logic        issue2_block_unsupported_o,
    output logic        issue2_block_serializing_o,
    output logic        issue2_block_busy_o,
    output logic        issue2_block_decode_o
);

  logic pair_valid;
  logic [31:0] inst1;
  logic [31:0] pc1;
  logic inst1_c;
  logic inst1_illegal;
  logic inst2_valid;
  logic [31:0] inst2;
  logic [31:0] pc2;
  logic inst2_c;
  logic inst2_illegal;

  logic inst2_consumed;
  logic recovery_kill;
  logic recovery_flush;
  logic pair_fire;

  cv32e40p_dual_issue_recovery recovery_i (
      .issue2_inflight_i   (issue2_pending_o),
      .branch_in_ex_i      (branch_in_ex_i),
      .branch_taken_i      (branch_taken_i),
      .jump_redirect_i     (jump_redirect_i),
      .exception_redirect_i(exception_redirect_i),
      .debug_redirect_i    (debug_redirect_i),
      .kill_issue2_o       (recovery_kill),
      .flush_pair_buffer_o (recovery_flush)
  );

  cv32e40p_hamsa_frontend #(
      .LINES(L0_LINES),
      .FPU  (FPU)
  ) frontend_i (
      .clk                (clk),
      .rst_n              (rst_n),
      .invalidate_i       (invalidate_l0_i),
      .redirect_i         (recovery_flush),
      .redirect_pc_i      (redirect_pc_i),
      .lookup_valid_i     (lookup_valid_i),
      .lookup_pc_i        (lookup_pc_i),
      .lookup_ready_o     (lookup_ready_o),
      .lookup_hit_o       (lookup_hit_o),
      .refill_valid_i     (refill_valid_i),
      .refill_addr_i      (refill_addr_i),
      .refill_data_i      (refill_data_i),
      .pair_valid_o       (pair_valid),
      .pair_ready_i       (issue1_ready_i),
      .inst1_o            (inst1),
      .pc1_o              (pc1),
      .inst1_compressed_o (inst1_c),
      .inst1_illegal_c_o  (inst1_illegal),
      .inst2_valid_o      (inst2_valid),
      .inst2_o            (inst2),
      .pc2_o              (pc2),
      .inst2_compressed_o (inst2_c),
      .inst2_illegal_c_o  (inst2_illegal),
      .next_pc_o          (next_pc_o)
  );

  assign issue1_valid_o      = pair_valid;
  assign issue1_instr_o      = inst1;
  assign issue1_pc_o         = pc1;
  assign issue1_compressed_o = inst1_c;
  assign issue1_illegal_c_o  = inst1_illegal;
  assign pair_fire           = pair_valid && issue1_ready_i;

  // This block-level integration top uses the mirrored-RF mode. Native 5R3W
  // integration is exercised by cv32e40p_core_hamsa_h2_5r3w.
  cv32e40p_hamsa_issue_cluster #(
      .NATIVE_5R3W(1'b0)
  ) issue_cluster_i (
      .clk                        (clk),
      .rst_n                      (rst_n),
      .flush_i                    (recovery_flush || recovery_kill),
      .pair_fire_i                (pair_fire),
      .primary_commit_safe_i      (primary_commit_safe_i),
      .inst1_valid_i              (pair_valid),
      .inst1_i                    (inst1),
      .inst2_valid_i              (inst2_valid && !inst2_illegal),
      .inst2_i                    (inst2),
      .primary_wb_we_i            (primary_wb_we_i),
      .primary_wb_addr_i          (primary_wb_addr_i),
      .primary_wb_data_i          (primary_wb_data_i),
      .primary_alu_we_i           (primary_alu_we_i),
      .primary_alu_addr_i         (primary_alu_addr_i),
      .primary_alu_data_i         (primary_alu_data_i),
      .primary_ex_we_i            (primary_ex_we_i),
      .primary_ex_addr_i          (primary_ex_addr_i),
      .primary_ex_data_i          (primary_ex_data_i),
      .issue2_rs1_addr_o          (),
      .issue2_rs2_addr_o          (),
      .issue2_rs1_data_i          (32'd0),
      .issue2_rs2_data_i          (32'd0),
      .issue2_rf_we_o             (),
      .issue2_rf_addr_o           (),
      .issue2_rf_data_o           (),
      .arb_alu_we_o               (arb_alu_we_o),
      .arb_alu_addr_o             (arb_alu_addr_o),
      .arb_alu_data_o             (arb_alu_data_o),
      .inst2_consumed_o           (inst2_consumed),
      .issue2_pending_o           (issue2_pending_o),
      .issue2_retired_o           (issue2_retired_o),
      .issue2_blocked_o           (issue2_blocked_o),
      .issue2_block_raw_o         (issue2_block_raw_o),
      .issue2_block_waw_o         (issue2_block_waw_o),
      .issue2_block_unsupported_o (issue2_block_unsupported_o),
      .issue2_block_serializing_o (issue2_block_serializing_o),
      .issue2_block_busy_o        (issue2_block_busy_o),
      .issue2_block_decode_o      (issue2_block_decode_o)
  );

  assign issue2_issued_o = inst2_consumed;
  assign issue2_killed_o = recovery_kill && issue2_pending_o;

  logic unused_pair_meta;
  assign unused_pair_meta = ^pc2 ^ inst2_c;

endmodule
