// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Functional golden/reference model for the SPARV MAC/DOTP datapath.
// This is NOT the final CORDIC microarchitecture. The paper specifies the
// supported SIMD precisions (4x8, 2x16, 1x32) and a resource-shared CORDIC
// implementation, but does not provide enough stage-level detail or opcode
// encoding to reproduce the exact synthesized unit. This block establishes
// bit-exact arithmetic behavior for verification of the later CORDIC datapath.

module cv32e40p_sparv_mac_dotp_ref (
    input  logic [31:0] operand_a_i,
    input  logic [31:0] operand_b_i,
    input  logic [63:0] accumulator_i,
    input  logic [1:0]  simd_mode_i,   // 00: 4x8, 01: 2x16, 10: 1x32
    input  logic        signed_a_i,
    input  logic        signed_b_i,
    input  logic        accumulate_i,
    output logic [63:0] result_o
);

  logic signed [63:0] sum;
  logic signed [63:0] a_ext;
  logic signed [63:0] b_ext;
  integer lane;

  always_comb begin
    sum = accumulate_i ? $signed(accumulator_i) : 64'sd0;
    a_ext = '0;
    b_ext = '0;

    unique case (simd_mode_i)
      2'b00: begin
        for (lane = 0; lane < 4; lane = lane + 1) begin
          a_ext = signed_a_i ? $signed({{56{operand_a_i[lane*8+7]}}, operand_a_i[lane*8 +: 8]})
                             : $signed({56'd0, operand_a_i[lane*8 +: 8]});
          b_ext = signed_b_i ? $signed({{56{operand_b_i[lane*8+7]}}, operand_b_i[lane*8 +: 8]})
                             : $signed({56'd0, operand_b_i[lane*8 +: 8]});
          sum = sum + (a_ext * b_ext);
        end
      end

      2'b01: begin
        for (lane = 0; lane < 2; lane = lane + 1) begin
          a_ext = signed_a_i ? $signed({{48{operand_a_i[lane*16+15]}}, operand_a_i[lane*16 +: 16]})
                             : $signed({48'd0, operand_a_i[lane*16 +: 16]});
          b_ext = signed_b_i ? $signed({{48{operand_b_i[lane*16+15]}}, operand_b_i[lane*16 +: 16]})
                             : $signed({48'd0, operand_b_i[lane*16 +: 16]});
          sum = sum + (a_ext * b_ext);
        end
      end

      2'b10: begin
        a_ext = signed_a_i ? $signed({{32{operand_a_i[31]}}, operand_a_i})
                           : $signed({32'd0, operand_a_i});
        b_ext = signed_b_i ? $signed({{32{operand_b_i[31]}}, operand_b_i})
                           : $signed({32'd0, operand_b_i});
        sum = sum + (a_ext * b_ext);
      end

      default: sum = accumulate_i ? $signed(accumulator_i) : 64'sd0;
    endcase

    result_o = sum;
  end

endmodule
