// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Asymmetric dual-issue cluster used to integrate HAMSA-DI behavior with the
// CV32E40P primary pipeline. Issue1 remains external/full-featured. This block
// decides whether the optional younger instruction can issue, obtains operands,
// applies cross-lane forwarding, executes the restricted Issue2 lane, and
// commits the younger result in-order.
//
// NATIVE_5R3W=0 uses the bring-up mirrored architectural RF and arbitrates
// Issue2 onto the legacy ALU write port. NATIVE_5R3W=1 obtains Issue2 operands
// from the shared 5R3W ID-stage RF and exposes a dedicated third write port.
// This provides the RF/PPA ablation without changing instruction semantics.

module cv32e40p_hamsa_issue_cluster #(
    parameter bit ENABLE_ISSUE2 = 1'b1,
    parameter bit NATIVE_5R3W   = 1'b0
) (
    input logic clk,
    input logic rst_n,

    input logic flush_i,
    input logic pair_fire_i,
    input logic primary_commit_safe_i,

    input  logic        inst1_valid_i,
    input  logic [31:0] inst1_i,
    input  logic        inst2_valid_i,
    input  logic [31:0] inst2_i,

    input logic        primary_wb_we_i,
    input logic [5:0]  primary_wb_addr_i,
    input logic [31:0] primary_wb_data_i,
    input logic        primary_alu_we_i,
    input logic [5:0]  primary_alu_addr_i,
    input logic [31:0] primary_alu_data_i,

    input logic        primary_ex_we_i,
    input logic [5:0]  primary_ex_addr_i,
    input logic [31:0] primary_ex_data_i,

    // Shared-5R3W RF operand path. Ignored when NATIVE_5R3W=0.
    output logic [5:0] issue2_rs1_addr_o,
    output logic [5:0] issue2_rs2_addr_o,
    input  logic [31:0] issue2_rs1_data_i,
    input  logic [31:0] issue2_rs2_data_i,

    // Dedicated third RF write port. Used only when NATIVE_5R3W=1.
    output logic        issue2_rf_we_o,
    output logic [5:0]  issue2_rf_addr_o,
    output logic [31:0] issue2_rf_data_o,

    // Legacy two-write-port arbitration path.
    output logic        arb_alu_we_o,
    output logic [5:0]  arb_alu_addr_o,
    output logic [31:0] arb_alu_data_o,

    output logic        inst2_consumed_o,
    output logic        issue2_pending_o,
    output logic        issue2_retired_o,
    output logic        issue2_blocked_o,

    output logic        issue2_block_raw_o,
    output logic        issue2_block_waw_o,
    output logic        issue2_block_unsupported_o,
    output logic        issue2_block_serializing_o,
    output logic        issue2_block_busy_o,
    output logic        issue2_block_decode_o
);

  logic issue1_valid;
  logic issue2_valid;
  logic raw_hazard;
  logic waw_hazard;
  logic issue2_unsupported;
  logic issue1_serializing;
  logic [4:0] inst1_rd;
  logic [4:0] inst2_rs1;
  logic [4:0] inst2_rs2;
  logic [4:0] inst2_rd;

  logic [31:0] rf_q [0:31];
  logic [31:0] rs1_base;
  logic [31:0] rs2_base;
  logic [31:0] rs1_fwd;
  logic [31:0] rs2_fwd;
  logic rs1_forwarded;
  logic rs2_forwarded;

  logic issue2_ready;
  logic issue2_illegal;
  logic issue2_wb_valid;
  logic [4:0] issue2_wb_rd;
  logic [31:0] issue2_wb_data;
  logic issue2_accept;
  logic issue2_commit;
  logic issue2_wb_ready;

  integer i;

  cv32e40p_dual_issue_idu #(
      .SPECULATE_BEHIND_BRANCH(1'b1)
  ) idu_i (
      .inst1_valid_i        (inst1_valid_i),
      .inst1_i              (inst1_i),
      .inst2_valid_i        (inst2_valid_i),
      .inst2_i              (inst2_i),
      .issue1_valid_o       (issue1_valid),
      .issue2_valid_o       (issue2_valid),
      .raw_hazard_o         (raw_hazard),
      .waw_hazard_o         (waw_hazard),
      .issue2_unsupported_o (issue2_unsupported),
      .issue1_serializing_o (issue1_serializing),
      .inst1_rd_o           (inst1_rd),
      .inst2_rs1_o          (inst2_rs1),
      .inst2_rs2_o          (inst2_rs2),
      .inst2_rd_o           (inst2_rd)
  );

  assign issue2_rs1_addr_o = {1'b0, inst2_rs1};
  assign issue2_rs2_addr_o = {1'b0, inst2_rs2};

  always_comb begin
    if (NATIVE_5R3W) begin
      rs1_base = issue2_rs1_data_i;
      rs2_base = issue2_rs2_data_i;
    end else begin
      rs1_base = (inst2_rs1 == 5'd0) ? 32'd0 : rf_q[inst2_rs1];
      rs2_base = (inst2_rs2 == 5'd0) ? 32'd0 : rf_q[inst2_rs2];
    end
  end

  cv32e40p_dual_issue_forwarding forwarding_i (
      .rs1_i             (inst2_rs1),
      .rs2_i             (inst2_rs2),
      .rs1_rf_i          (rs1_base),
      .rs2_rf_i          (rs2_base),
      .ex1_we_i          (primary_ex_we_i),
      .ex1_rd_i          (primary_ex_addr_i[4:0]),
      .ex1_data_i        (primary_ex_data_i),
      .ex2_we_i          (1'b0),
      .ex2_rd_i          ('0),
      .ex2_data_i        ('0),
      .wb1_we_i          (primary_wb_we_i),
      .wb1_rd_i          (primary_wb_addr_i[4:0]),
      .wb1_data_i        (primary_wb_data_i),
      .wb2_we_i          (issue2_wb_valid),
      .wb2_rd_i          (issue2_wb_rd),
      .wb2_data_i        (issue2_wb_data),
      .rs1_o             (rs1_fwd),
      .rs2_o             (rs2_fwd),
      .rs1_forwarded_o   (rs1_forwarded),
      .rs2_forwarded_o   (rs2_forwarded)
  );

  assign issue2_accept = ENABLE_ISSUE2 && pair_fire_i && issue2_valid && issue2_ready;

  // A true third write port removes ALU-port structural contention. Ordering is
  // still enforced by primary_commit_safe_i.
  assign issue2_wb_ready = ENABLE_ISSUE2 && primary_commit_safe_i &&
                           (NATIVE_5R3W || !primary_alu_we_i);

  cv32e40p_issue2_lane issue2_lane_i (
      .clk             (clk),
      .rst_n           (rst_n),
      .issue_valid_i   (issue2_accept),
      .instr_i         (inst2_i),
      .rs1_data_i      (rs1_fwd),
      .rs2_data_i      (rs2_fwd),
      .kill_i          (flush_i || !ENABLE_ISSUE2),
      .wb_ready_i      (issue2_wb_ready),
      .issue_ready_o   (issue2_ready),
      .decode_illegal_o(issue2_illegal),
      .wb_valid_o      (issue2_wb_valid),
      .wb_rd_o         (issue2_wb_rd),
      .wb_data_o       (issue2_wb_data)
  );

  always_comb begin
    arb_alu_we_o   = primary_alu_we_i;
    arb_alu_addr_o = primary_alu_addr_i;
    arb_alu_data_o = primary_alu_data_i;

    if (!NATIVE_5R3W && ENABLE_ISSUE2 && !primary_alu_we_i &&
        primary_commit_safe_i && issue2_wb_valid) begin
      arb_alu_we_o   = (issue2_wb_rd != 5'd0);
      arb_alu_addr_o = {1'b0, issue2_wb_rd};
      arb_alu_data_o = issue2_wb_data;
    end
  end

  assign issue2_commit = ENABLE_ISSUE2 && issue2_wb_valid && issue2_wb_ready &&
                         (issue2_wb_rd != 5'd0);

  assign issue2_rf_we_o   = NATIVE_5R3W && issue2_commit;
  assign issue2_rf_addr_o = {1'b0, issue2_wb_rd};
  assign issue2_rf_data_o = issue2_wb_data;

  // Shadow architectural state is retained only for the bring-up RF mode.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 32; i++) rf_q[i] <= 32'd0;
    end else begin
      rf_q[0] <= 32'd0;
      if (!NATIVE_5R3W) begin
        if (issue2_commit)
          rf_q[issue2_wb_rd] <= issue2_wb_data;

        if (primary_wb_we_i && !primary_wb_addr_i[5] &&
            (primary_wb_addr_i[4:0] != 5'd0))
          rf_q[primary_wb_addr_i[4:0]] <= primary_wb_data_i;

        if (primary_alu_we_i && !primary_alu_addr_i[5] &&
            (primary_alu_addr_i[4:0] != 5'd0))
          rf_q[primary_alu_addr_i[4:0]] <= primary_alu_data_i;
      end
    end
  end

  assign inst2_consumed_o = ENABLE_ISSUE2 && issue2_accept;
  assign issue2_pending_o  = ENABLE_ISSUE2 && issue2_wb_valid;
  assign issue2_retired_o  = ENABLE_ISSUE2 && issue2_commit;

  assign issue2_blocked_o  = ENABLE_ISSUE2 && inst1_valid_i && inst2_valid_i &&
                             (!issue2_valid || !issue2_ready || issue2_illegal);

  assign issue2_block_raw_o         = issue2_blocked_o && raw_hazard;
  assign issue2_block_waw_o         = issue2_blocked_o && waw_hazard;
  assign issue2_block_unsupported_o = issue2_blocked_o && issue2_unsupported;
  assign issue2_block_serializing_o = issue2_blocked_o && issue1_serializing;
  assign issue2_block_busy_o        = issue2_blocked_o && !issue2_ready;
  assign issue2_block_decode_o      = issue2_blocked_o && issue2_illegal;

  logic unused_status;
  assign unused_status = issue1_valid ^ inst1_rd[0] ^ inst2_rd[0] ^
                         rs1_forwarded ^ rs2_forwarded;

endmodule
