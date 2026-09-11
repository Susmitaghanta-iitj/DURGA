// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Integrated dual-issue pair unit used for directed verification and RF/PPA
// exploration. It combines the IDU, restricted Issue2 lane and native 5R3W RF.

module cv32e40p_dual_issue_pair_unit #(
    parameter int FPU = 0,
    parameter int PULP_ZFINX = 0
) (
    input logic clk,
    input logic rst_n,

    input  logic        inst1_valid_i,
    input  logic [31:0] inst1_i,
    input  logic        inst2_valid_i,
    input  logic [31:0] inst2_i,

    input logic [5:0] issue1_raddr_a_i,
    output logic [31:0] issue1_rdata_a_o,
    input logic [5:0] issue1_raddr_b_i,
    output logic [31:0] issue1_rdata_b_o,
    input logic [5:0] issue1_raddr_c_i,
    output logic [31:0] issue1_rdata_c_o,

    input logic [5:0] issue1_waddr_a_i,
    input logic [31:0] issue1_wdata_a_i,
    input logic issue1_we_a_i,
    input logic [5:0] issue1_waddr_b_i,
    input logic [31:0] issue1_wdata_b_i,
    input logic issue1_we_b_i,

    input logic issue2_kill_i,
    input logic issue2_wb_ready,

    output logic issue1_valid_o,
    output logic issue2_valid_o,
    output logic issue2_fire_o,
    output logic issue2_decode_illegal_o,
    output logic issue2_wb_valid_o,
    output logic [4:0] issue2_wb_rd_o,
    output logic [31:0] issue2_wb_data_o,
    output logic raw_hazard_o,
    output logic waw_hazard_o,
    output logic issue2_unsupported_o,
    output logic issue1_serializing_o
);

  logic [4:0] inst1_rd;
  logic [4:0] inst2_rs1;
  logic [4:0] inst2_rs2;
  logic [4:0] inst2_rd;
  logic issue2_candidate;
  logic issue2_ready;
  logic [31:0] issue2_rs1_data;
  logic [31:0] issue2_rs2_data;

  cv32e40p_dual_issue_idu idu_i (
      .inst1_valid_i(inst1_valid_i),
      .inst1_i(inst1_i),
      .inst2_valid_i(inst2_valid_i),
      .inst2_i(inst2_i),
      .issue1_valid_o(issue1_valid_o),
      .issue2_valid_o(issue2_candidate),
      .raw_hazard_o(raw_hazard_o),
      .waw_hazard_o(waw_hazard_o),
      .issue2_unsupported_o(issue2_unsupported_o),
      .issue1_serializing_o(issue1_serializing_o),
      .inst1_rd_o(inst1_rd),
      .inst2_rs1_o(inst2_rs1),
      .inst2_rs2_o(inst2_rs2),
      .inst2_rd_o(inst2_rd)
  );

  assign issue2_valid_o = issue2_candidate && issue2_ready;
  assign issue2_fire_o  = issue2_valid_o;

  cv32e40p_issue2_lane issue2_lane_i (
      .clk             (clk),
      .rst_n           (rst_n),
      .issue_valid_i   (issue2_valid_o),
      .instr_i         (inst2_i),
      .rs1_data_i      (issue2_rs1_data),
      .rs2_data_i      (issue2_rs2_data),
      .kill_i          (issue2_kill_i),
      .wb_ready_i      (issue2_wb_ready),
      .issue_ready_o   (issue2_ready),
      .decode_illegal_o(issue2_decode_illegal_o),
      .wb_valid_o      (issue2_wb_valid_o),
      .wb_rd_o         (issue2_wb_rd_o),
      .wb_data_o       (issue2_wb_data_o)
  );

  cv32e40p_register_file_5r3w #(
      .ADDR_WIDTH(6),
      .DATA_WIDTH(32),
      .FPU       (FPU),
      .PULP_ZFINX(PULP_ZFINX)
  ) register_file_i (
      .clk      (clk),
      .rst_n    (rst_n),
      .scan_cg_en_i(1'b0),

      .raddr_a_i(issue1_raddr_a_i),
      .rdata_a_o(issue1_rdata_a_o),
      .raddr_b_i(issue1_raddr_b_i),
      .rdata_b_o(issue1_rdata_b_o),
      .raddr_c_i(issue1_raddr_c_i),
      .rdata_c_o(issue1_rdata_c_o),
      .raddr_d_i({1'b0, inst2_rs1}),
      .rdata_d_o(issue2_rs1_data),
      .raddr_e_i({1'b0, inst2_rs2}),
      .rdata_e_o(issue2_rs2_data),

      .waddr_a_i(issue1_waddr_a_i),
      .wdata_a_i(issue1_wdata_a_i),
      .we_a_i   (issue1_we_a_i),
      .waddr_b_i(issue1_waddr_b_i),
      .wdata_b_i(issue1_wdata_b_i),
      .we_b_i   (issue1_we_b_i),
      .waddr_c_i({1'b0, issue2_wb_rd_o}),
      .wdata_c_i(issue2_wb_data_o),
      .we_c_i   (issue2_wb_valid_o && !issue2_kill_i)
  );

  logic unused_idu_outputs;
  assign unused_idu_outputs = ^{inst1_rd, inst2_rd};

endmodule
