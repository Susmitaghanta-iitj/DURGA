// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Secondary execution lane for the asymmetric dual-issue prototype.
// Supports scalar RV32I ALU operations and a compact single-cycle RV32M MUL.

module cv32e40p_issue2_ex
  import cv32e40p_pkg::*;
(
    input logic clk,
    input logic rst_n,

    input logic        valid_i,
    input alu_opcode_e alu_operator_i,
    input logic        mul_en_i,
    input logic [31:0] operand_a_i,
    input logic [31:0] operand_b_i,
    input logic [4:0]  rd_i,

    input  logic        kill_i,
    input  logic        wb_ready_i,

    output logic        ready_o,
    output logic        valid_o,
    output logic [4:0]  rd_o,
    output logic [31:0] result_o
);

  logic [31:0] alu_result;
  logic        alu_cmp_result;
  logic        alu_ready;
  logic [31:0] mul_result;

  logic        valid_q;
  logic [4:0]  rd_q;
  logic [31:0] result_q;

  assign ready_o    = !valid_q || wb_ready_i;
  assign mul_result = operand_a_i * operand_b_i;

  cv32e40p_alu alu_issue2_i (
      .clk                (clk),
      .rst_n              (rst_n),
      .enable_i           (valid_i && ready_o && !mul_en_i),
      .operator_i         (alu_operator_i),
      .operand_a_i        (operand_a_i),
      .operand_b_i        (operand_b_i),
      .operand_c_i        (32'b0),
      // cv32e40p_alu declares a 2-bit vector-mode input.  Scalar 32-bit mode
      // is encoded as 2'b00; use the explicit width to avoid tool-dependent
      // padding of the one-bit legacy VEC_MODE32 constant.
      .vector_mode_i      (2'b00),
      .bmask_a_i          (5'b0),
      .bmask_b_i          (5'b0),
      .imm_vec_ext_i      (2'b0),
      .is_clpx_i          (1'b0),
      .is_subrot_i        (1'b0),
      .clpx_shift_i       (2'b0),
      .result_o           (alu_result),
      .comparison_result_o(alu_cmp_result),
      .ready_o            (alu_ready),
      .ex_ready_i         (ready_o)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q  <= 1'b0;
      rd_q     <= '0;
      result_q <= '0;
    end else begin
      if (kill_i) begin
        valid_q <= 1'b0;
      end else if (ready_o) begin
        valid_q <= valid_i && (mul_en_i || alu_ready);
        if (valid_i && (mul_en_i || alu_ready)) begin
          rd_q     <= rd_i;
          result_q <= mul_en_i ? mul_result : alu_result;
        end
      end
    end
  end

  assign valid_o  = valid_q;
  assign rd_o     = rd_q;
  assign result_o = result_q;

  logic unused_cmp;
  assign unused_cmp = alu_cmp_result;

endmodule
