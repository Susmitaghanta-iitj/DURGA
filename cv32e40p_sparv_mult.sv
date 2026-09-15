// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// SPARV-compatible multiplier wrapper.
//
// The existing CV32E40P multiplier remains the source of truth for integer,
// high-half, rounded, MSU and complex-vector behavior. Standard scalar MAC,
// 4x8-bit DOTP and 2x16-bit DOTP operations are redirected to the SPARV
// multicycle engine so the existing Xpulp decode can exercise the accelerated
// datapath without inventing a new opcode table.

module cv32e40p_sparv_mult
  import cv32e40p_pkg::*;
(
    input logic clk,
    input logic rst_n,

    input logic        enable_i,
    input mul_opcode_e operator_i,

    input logic       short_subword_i,
    input logic [1:0] short_signed_i,

    input logic [31:0] op_a_i,
    input logic [31:0] op_b_i,
    input logic [31:0] op_c_i,
    input logic [4:0]  imm_i,

    input logic [1:0]  dot_signed_i,
    input logic [31:0] dot_op_a_i,
    input logic [31:0] dot_op_b_i,
    input logic [31:0] dot_op_c_i,
    input logic        is_clpx_i,
    input logic [1:0]  clpx_shift_i,
    input logic        clpx_img_i,

    output logic [31:0] result_o,
    output logic        multicycle_o,
    output logic        ready_o,
    input  logic        ex_ready_i
);

  logic baseline_enable;
  logic [31:0] baseline_result;
  logic baseline_multicycle;
  logic baseline_ready;

  logic accel_select;
  logic accel_ready;
  logic accel_result_valid;
  logic [63:0] accel_result;
  logic accel_busy;
  logic [1:0] accel_mode;
  logic [31:0] accel_a;
  logic [31:0] accel_b;
  logic [63:0] accel_c;
  logic accel_signed_a;
  logic accel_signed_b;
  logic accel_accumulate;

  always_comb begin
    accel_select     = 1'b0;
    accel_mode       = 2'b10;
    accel_a          = op_a_i;
    accel_b          = op_b_i;
    accel_c          = {{32{op_c_i[31]}}, op_c_i};
    accel_signed_a   = 1'b1;
    accel_signed_b   = 1'b1;
    accel_accumulate = 1'b1;

    unique case (operator_i)
      MUL_MAC32: begin
        accel_select = 1'b1;
        accel_mode   = 2'b10;
      end

      MUL_DOT8: begin
        accel_select     = 1'b1;
        accel_mode       = 2'b00;
        accel_a          = dot_op_a_i;
        accel_b          = dot_op_b_i;
        accel_c          = {{32{dot_op_c_i[31]}}, dot_op_c_i};
        accel_signed_a   = dot_signed_i[1];
        accel_signed_b   = dot_signed_i[0];
      end

      MUL_DOT16: begin
        // Complex 16-bit PULP operations use cross-lane/negation semantics not
        // represented by the generic SPARV DOTP contract, so they remain on
        // the fully compatible baseline datapath.
        if (!is_clpx_i) begin
          accel_select     = 1'b1;
          accel_mode       = 2'b01;
          accel_a          = dot_op_a_i;
          accel_b          = dot_op_b_i;
          accel_c          = {{32{dot_op_c_i[31]}}, dot_op_c_i};
          accel_signed_a   = dot_signed_i[1];
          accel_signed_b   = dot_signed_i[0];
        end
      end

      default: begin
        accel_select = 1'b0;
      end
    endcase
  end

  assign baseline_enable = enable_i && !accel_select;

  cv32e40p_mult baseline_i (
      .clk(clk),
      .rst_n(rst_n),
      .enable_i(baseline_enable),
      .operator_i(operator_i),
      .short_subword_i(short_subword_i),
      .short_signed_i(short_signed_i),
      .op_a_i(op_a_i),
      .op_b_i(op_b_i),
      .op_c_i(op_c_i),
      .imm_i(imm_i),
      .dot_signed_i(dot_signed_i),
      .dot_op_a_i(dot_op_a_i),
      .dot_op_b_i(dot_op_b_i),
      .dot_op_c_i(dot_op_c_i),
      .is_clpx_i(is_clpx_i),
      .clpx_shift_i(clpx_shift_i),
      .clpx_img_i(clpx_img_i),
      .result_o(baseline_result),
      .multicycle_o(baseline_multicycle),
      .ready_o(baseline_ready),
      .ex_ready_i(ex_ready_i)
  );

  cv32e40p_sparv_mac_dotp_engine accel_i (
      .clk(clk),
      .rst_n(rst_n),
      .kill_i(1'b0),
      .valid_i(enable_i && accel_select && accel_ready),
      .ready_o(accel_ready),
      .operand_a_i(accel_a),
      .operand_b_i(accel_b),
      .accumulator_i(accel_c),
      .simd_mode_i(accel_mode),
      .signed_a_i(accel_signed_a),
      .signed_b_i(accel_signed_b),
      .accumulate_i(accel_accumulate),
      .result_valid_o(accel_result_valid),
      .result_ready_i(accel_result_valid && ex_ready_i),
      .result_o(accel_result),
      .busy_o(accel_busy)
  );

  always_comb begin
    if (accel_select) begin
      result_o     = accel_result[31:0];
      ready_o      = accel_result_valid;
      multicycle_o = accel_busy && !accel_result_valid;
    end else begin
      result_o     = baseline_result;
      ready_o      = baseline_ready;
      multicycle_o = baseline_multicycle;
    end
  end

endmodule
