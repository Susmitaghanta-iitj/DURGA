// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Integration bridge for the HAMSA-style asymmetric Issue2 path.
//
// This block is intentionally conservative. It can be inserted between the
// existing IF/ID boundary and the existing ALU writeback port without changing
// the architectural decode/execute path for Issue1. A shadow integer register
// file mirrors all committed primary writes and supplies operands to Issue2.
// Issue2 results are offered to the existing ALU write port only when that port
// is not used by the primary pipeline. This lets us validate real architectural
// Issue2 execution before replacing the ID-stage RF with the native 5R3W RF.
//
// Integration contract:
//   * inst1_valid_i/inst1_i are the instruction presented to the normal ID stage.
//   * inst2_* is the optional sequential partner from the pair buffer.
//   * primary_wb_{a,b} mirror the two existing architectural RF write ports.
//   * primary_alu_* is the existing ALU forwarding/write port from EX to ID/RF.
//   * arb_alu_* replaces that connection. Primary always has priority.
//   * pair_fire_i must pulse only when Issue1 is accepted by ID.
//
// The shadow RF is a bring-up mechanism, not the final PPA solution. Once the
// 5R3W RF is integrated directly in cv32e40p_id_stage, this bridge can be reduced
// to pairing/issue control and forwarding arbitration.

module cv32e40p_dual_issue_integration_bridge (
    input logic clk,
    input logic rst_n,

    input logic pair_fire_i,
    input logic flush_i,

    input logic        inst1_valid_i,
    input logic [31:0] inst1_i,
    input logic        inst2_valid_i,
    input logic [31:0] inst2_i,

    // Existing architectural writes, mirrored into the shadow RF.
    input logic        primary_wb_a_we_i,
    input logic [5:0]  primary_wb_a_addr_i,
    input logic [31:0] primary_wb_a_data_i,
    input logic        primary_wb_b_we_i,
    input logic [5:0]  primary_wb_b_addr_i,
    input logic [31:0] primary_wb_b_data_i,

    // Existing ALU forwarding/write port. Primary has priority.
    input logic        primary_alu_we_i,
    input logic [5:0]  primary_alu_addr_i,
    input logic [31:0] primary_alu_data_i,

    output logic        arb_alu_we_o,
    output logic [5:0]  arb_alu_addr_o,
    output logic [31:0] arb_alu_data_o,

    output logic issue2_issued_o,
    output logic issue2_blocked_o,
    output logic issue2_wb_pending_o
);

  logic idu_issue1_valid;
  logic idu_issue2_valid;
  logic idu_raw_hazard;
  logic idu_waw_hazard;
  logic idu_unsupported;
  logic idu_serializing;
  logic [4:0] inst1_rd;
  logic [4:0] inst2_rs1;
  logic [4:0] inst2_rs2;
  logic [4:0] inst2_rd;

  logic [31:0] shadow_rf [0:31];
  integer i;

  logic [31:0] issue2_rs1_data;
  logic [31:0] issue2_rs2_data;
  logic issue2_ready;
  logic issue2_illegal;
  logic issue2_wb_valid;
  logic [4:0] issue2_wb_rd;
  logic [31:0] issue2_wb_data;
  logic issue2_accept;
  logic issue2_commit;

  cv32e40p_dual_issue_idu idu_i (
      .inst1_valid_i        (inst1_valid_i),
      .inst1_i              (inst1_i),
      .inst2_valid_i        (inst2_valid_i),
      .inst2_i              (inst2_i),
      .issue1_valid_o       (idu_issue1_valid),
      .issue2_valid_o       (idu_issue2_valid),
      .raw_hazard_o         (idu_raw_hazard),
      .waw_hazard_o         (idu_waw_hazard),
      .issue2_unsupported_o (idu_unsupported),
      .issue1_serializing_o (idu_serializing),
      .inst1_rd_o           (inst1_rd),
      .inst2_rs1_o          (inst2_rs1),
      .inst2_rs2_o          (inst2_rs2),
      .inst2_rd_o           (inst2_rd)
  );

  assign issue2_rs1_data = (inst2_rs1 == 5'd0) ? 32'd0 : shadow_rf[inst2_rs1];
  assign issue2_rs2_data = (inst2_rs2 == 5'd0) ? 32'd0 : shadow_rf[inst2_rs2];

  // Accept the younger instruction only on the same cycle as the architectural
  // acceptance of Issue1. Backpressure from the Issue2 one-entry buffer simply
  // disables pairing for that cycle; Issue1 is never stalled by Issue2.
  assign issue2_accept = pair_fire_i && idu_issue2_valid && issue2_ready;

  cv32e40p_issue2_lane issue2_lane_i (
      .clk             (clk),
      .rst_n           (rst_n),
      .issue_valid_i   (issue2_accept),
      .instr_i         (inst2_i),
      .rs1_data_i      (issue2_rs1_data),
      .rs2_data_i      (issue2_rs2_data),
      .kill_i          (flush_i),
      .wb_ready_i      (!primary_alu_we_i),
      .issue_ready_o   (issue2_ready),
      .decode_illegal_o(issue2_illegal),
      .wb_valid_o      (issue2_wb_valid),
      .wb_rd_o         (issue2_wb_rd),
      .wb_data_o       (issue2_wb_data)
  );

  // Existing primary ALU write has absolute priority. Issue2 holds its one-entry
  // buffer until the port becomes free.
  always_comb begin
    arb_alu_we_o   = primary_alu_we_i;
    arb_alu_addr_o = primary_alu_addr_i;
    arb_alu_data_o = primary_alu_data_i;

    if (!primary_alu_we_i && issue2_wb_valid) begin
      arb_alu_we_o   = (issue2_wb_rd != 5'd0);
      arb_alu_addr_o = {1'b0, issue2_wb_rd};
      arb_alu_data_o = issue2_wb_data;
    end
  end

  assign issue2_commit = issue2_wb_valid && !primary_alu_we_i && (issue2_wb_rd != 5'd0);

  // Shadow RF mirrors both original architectural write ports and the committed
  // Issue2 result. Priority follows architectural age: primary B > primary A >
  // Issue2 for any accidental same-address collision. The IDU already prevents
  // normal Issue1/Issue2 WAW pairs.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 32; i++) shadow_rf[i] <= 32'd0;
    end else begin
      shadow_rf[0] <= 32'd0;

      if (issue2_commit)
        shadow_rf[issue2_wb_rd] <= issue2_wb_data;

      if (primary_wb_a_we_i && !primary_wb_a_addr_i[5] &&
          (primary_wb_a_addr_i[4:0] != 5'd0))
        shadow_rf[primary_wb_a_addr_i[4:0]] <= primary_wb_a_data_i;

      if (primary_wb_b_we_i && !primary_wb_b_addr_i[5] &&
          (primary_wb_b_addr_i[4:0] != 5'd0))
        shadow_rf[primary_wb_b_addr_i[4:0]] <= primary_wb_b_data_i;
    end
  end

  assign issue2_issued_o     = issue2_accept;
  assign issue2_wb_pending_o = issue2_wb_valid;
  assign issue2_blocked_o    = inst1_valid_i && inst2_valid_i &&
                               (!idu_issue2_valid || !issue2_ready || issue2_illegal);

  // Silence conservative bring-up signals that are useful for waveform debug.
  logic unused_debug;
  assign unused_debug = idu_issue1_valid ^ idu_raw_hazard ^ idu_waw_hazard ^
                        idu_unsupported ^ idu_serializing ^ inst1_rd[0] ^ inst2_rd[0];

endmodule
