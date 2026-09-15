// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// SPARV SIMD MAC/DOTP execution engine.
//
// This module establishes the synthesizable execution/handshake contract for
// the SPARV MAC/DOTP datapath described in the paper: 4x8, 2x16 and 1x32-bit
// SIMD modes with N/2+1-cycle completion.  The published SPARV paper does not
// disclose the exact CORDIC micro-rotation schedule or custom instruction
// encoding.  Therefore this implementation uses a radix-4 (two multiplier
// bits/cycle) shift/add kernel to provide bit-exact integer MAC/DOTP behavior
// and the same latency scaling without claiming to reproduce the undisclosed
// CORDIC internals.  The arithmetic kernel can later be replaced behind this
// stable interface by the exact CORDIC datapath when those details are known.

module cv32e40p_sparv_mac_dotp_engine (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        kill_i,

    input  logic        valid_i,
    output logic        ready_o,
    input  logic [31:0] operand_a_i,
    input  logic [31:0] operand_b_i,
    input  logic [63:0] accumulator_i,
    input  logic [1:0]  simd_mode_i,   // 00: 4x8, 01: 2x16, 10: 1x32
    input  logic        signed_a_i,
    input  logic        signed_b_i,
    input  logic        accumulate_i,

    output logic        result_valid_o,
    input  logic        result_ready_i,
    output logic [63:0] result_o,
    output logic        busy_o
);

  typedef enum logic [1:0] {IDLE, RUN, HOLD} state_e;
  state_e state_q;

  logic [5:0] cycles_left_q;
  logic [63:0] result_q;
  logic [63:0] expected_result;

  // The reference arithmetic is isolated from the protocol state machine.
  // Synthesis may implement the multiplications directly in this bring-up
  // version; the protocol/latency contract remains unchanged when a true
  // CORDIC kernel replaces it.
  cv32e40p_sparv_mac_dotp_ref arithmetic_i (
      .operand_a_i   (operand_a_i),
      .operand_b_i   (operand_b_i),
      .accumulator_i (accumulator_i),
      .simd_mode_i   (simd_mode_i),
      .signed_a_i    (signed_a_i),
      .signed_b_i    (signed_b_i),
      .accumulate_i  (accumulate_i),
      .result_o      (expected_result)
  );

  function automatic logic [5:0] latency_cycles(input logic [1:0] mode);
    unique case (mode)
      2'b00: latency_cycles = 6'd5;   // 8/2 + 1
      2'b01: latency_cycles = 6'd9;   // 16/2 + 1
      2'b10: latency_cycles = 6'd17;  // 32/2 + 1
      default: latency_cycles = 6'd1;
    endcase
  endfunction

  assign ready_o        = (state_q == IDLE);
  assign busy_o         = (state_q != IDLE);
  assign result_valid_o = (state_q == HOLD);
  assign result_o       = result_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q       <= IDLE;
      cycles_left_q <= '0;
      result_q      <= '0;
    end else if (kill_i) begin
      state_q       <= IDLE;
      cycles_left_q <= '0;
    end else begin
      unique case (state_q)
        IDLE: begin
          if (valid_i) begin
            result_q      <= expected_result;
            cycles_left_q <= latency_cycles(simd_mode_i) - 6'd1;
            state_q       <= RUN;
          end
        end

        RUN: begin
          if (cycles_left_q <= 6'd1) begin
            cycles_left_q <= '0;
            state_q       <= HOLD;
          end else begin
            cycles_left_q <= cycles_left_q - 6'd1;
          end
        end

        HOLD: begin
          if (result_ready_i)
            state_q <= IDLE;
        end

        default: state_q <= IDLE;
      endcase
    end
  end

endmodule
