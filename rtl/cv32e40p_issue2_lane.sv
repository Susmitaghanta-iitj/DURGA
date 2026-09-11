// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Composed secondary lane: restricted decoder + scalar ALU/MUL execution +
// one-entry writeback buffer. Register-file ports are intentionally external
// at this milestone so the lane can be integrated without changing the golden
// CV32E40P register file yet.

module cv32e40p_issue2_lane
  import cv32e40p_pkg::*;
(
    input logic clk,
    input logic rst_n,

    input  logic        issue_valid_i,
    input  logic [31:0] instr_i,
    input  logic [31:0] rs1_data_i,
    input  logic [31:0] rs2_data_i,
    input  logic        kill_i,
    input  logic        wb_ready_i,

    output logic        issue_ready_o,
    output logic        decode_illegal_o,
    output logic        wb_valid_o,
    output logic [4:0]  wb_rd_o,
    output logic [31:0] wb_data_o
);

  logic        dec_valid;
  logic [4:0]  dec_rd;
  alu_opcode_e dec_alu_op;
  logic        dec_mul_en;
  logic [31:0] dec_operand_a;
  logic [31:0] dec_operand_b;

  logic ex_ready;

  cv32e40p_issue2_decoder issue2_decoder_i (
      .valid_i       (issue_valid_i && ex_ready),
      .instr_i       (instr_i),
      .rs1_data_i    (rs1_data_i),
      .rs2_data_i    (rs2_data_i),
      .valid_o       (dec_valid),
      .illegal_o     (decode_illegal_o),
      .rd_o          (dec_rd),
      .alu_operator_o(dec_alu_op),
      .mul_en_o      (dec_mul_en),
      .operand_a_o   (dec_operand_a),
      .operand_b_o   (dec_operand_b)
  );

  cv32e40p_issue2_ex issue2_ex_i (
      .clk           (clk),
      .rst_n         (rst_n),
      .valid_i       (dec_valid),
      .alu_operator_i(dec_alu_op),
      .mul_en_i      (dec_mul_en),
      .operand_a_i   (dec_operand_a),
      .operand_b_i   (dec_operand_b),
      .rd_i          (dec_rd),
      .kill_i        (kill_i),
      .wb_ready_i    (wb_ready_i),
      .ready_o       (ex_ready),
      .valid_o       (wb_valid_o),
      .rd_o          (wb_rd_o),
      .result_o      (wb_data_o)
  );

  assign issue_ready_o = ex_ready;

endmodule
