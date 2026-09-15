// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Prototype two-instruction assembly buffer for the existing 32-bit CV32E40P
// frontend. It does not increase fetch bandwidth; it assembles two sequential
// fixed-width instructions so the dual-issue backend can be validated before a
// wider/L0 frontend is introduced.
//
// Compressed instructions are serialized in this milestone. A redirect flushes
// all buffered state. Crucially, instruction 2 is replayed as the next Issue1
// instruction whenever the backend cannot consume it in parallel; this keeps
// architectural execution lossless when RAW/WAW/unsupported pairing blocks.

module cv32e40p_dual_fetch_pair_buffer (
    input logic clk,
    input logic rst_n,

    input logic flush_i,

    input  logic        in_valid_i,
    input  logic [31:0] in_instr_i,
    input  logic [31:0] in_pc_i,
    input  logic        in_compressed_i,
    input  logic        in_illegal_c_i,
    input  logic        in_fetch_failed_i,
    output logic        in_ready_o,

    output logic        out_valid_o,
    output logic [31:0] out_inst1_o,
    output logic [31:0] out_pc1_o,
    output logic        out_inst1_compressed_o,
    output logic        out_inst1_illegal_c_o,
    output logic        out_inst1_fetch_failed_o,
    output logic        out_inst2_valid_o,
    output logic [31:0] out_inst2_o,
    output logic [31:0] out_pc2_o,
    // out_ready consumes instruction 1. The second instruction is consumed only
    // when out_inst2_consumed_i is high; otherwise it is replayed as next inst1.
    input  logic        out_ready_i,
    input  logic        out_inst2_consumed_i
);

  logic        first_valid_q;
  logic [31:0] first_instr_q;
  logic [31:0] first_pc_q;
  logic        first_compressed_q;
  logic        first_illegal_c_q;
  logic        first_fetch_failed_q;

  logic        out_valid_q;
  logic [31:0] out_inst1_q;
  logic [31:0] out_pc1_q;
  logic        out_inst1_compressed_q;
  logic        out_inst1_illegal_c_q;
  logic        out_inst1_fetch_failed_q;
  logic        out_inst2_valid_q;
  logic [31:0] out_inst2_q;
  logic [31:0] out_pc2_q;
  logic        out_inst2_fetch_failed_q;

  logic out_slot_free;
  logic in_fire;
  logic can_pair;

  assign out_slot_free = !out_valid_q || out_ready_i;
  assign in_ready_o     = out_slot_free && !(out_valid_q && out_ready_i &&
                                             out_inst2_valid_q && !out_inst2_consumed_i);
  assign in_fire        = in_valid_i && in_ready_o;

  assign can_pair = first_valid_q && !first_compressed_q && !in_compressed_i &&
                    !first_illegal_c_q && !in_illegal_c_i &&
                    (in_pc_i == (first_pc_q + 32'd4));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      first_valid_q             <= 1'b0;
      first_instr_q             <= '0;
      first_pc_q                <= '0;
      first_compressed_q        <= 1'b0;
      first_illegal_c_q         <= 1'b0;
      first_fetch_failed_q      <= 1'b0;
      out_valid_q               <= 1'b0;
      out_inst1_q               <= '0;
      out_pc1_q                 <= '0;
      out_inst1_compressed_q    <= 1'b0;
      out_inst1_illegal_c_q     <= 1'b0;
      out_inst1_fetch_failed_q  <= 1'b0;
      out_inst2_valid_q         <= 1'b0;
      out_inst2_q               <= '0;
      out_pc2_q                 <= '0;
      out_inst2_fetch_failed_q  <= 1'b0;
    end else if (flush_i) begin
      first_valid_q       <= 1'b0;
      out_valid_q         <= 1'b0;
      out_inst2_valid_q   <= 1'b0;
    end else begin
      if (out_valid_q && out_ready_i) begin
        out_valid_q       <= 1'b0;
        out_inst2_valid_q <= 1'b0;

        // If Issue2 was not accepted, replay it as the next architectural
        // instruction instead of dropping it.
        if (out_inst2_valid_q && !out_inst2_consumed_i) begin
          first_valid_q        <= 1'b1;
          first_instr_q        <= out_inst2_q;
          first_pc_q           <= out_pc2_q;
          first_compressed_q   <= 1'b0;
          first_illegal_c_q    <= 1'b0;
          first_fetch_failed_q <= out_inst2_fetch_failed_q;
        end
      end

      if (in_fire) begin
        if (!first_valid_q) begin
          // A compressed or fault-marked instruction is emitted immediately as
          // a serialized single; a normal uncompressed instruction waits for a
          // possible partner.
          if (in_compressed_i || in_illegal_c_i || in_fetch_failed_i) begin
            out_valid_q               <= 1'b1;
            out_inst1_q               <= in_instr_i;
            out_pc1_q                 <= in_pc_i;
            out_inst1_compressed_q    <= in_compressed_i;
            out_inst1_illegal_c_q     <= in_illegal_c_i;
            out_inst1_fetch_failed_q  <= in_fetch_failed_i;
            out_inst2_valid_q         <= 1'b0;
            first_valid_q             <= 1'b0;
          end else begin
            first_valid_q        <= 1'b1;
            first_instr_q        <= in_instr_i;
            first_pc_q           <= in_pc_i;
            first_compressed_q   <= 1'b0;
            first_illegal_c_q    <= 1'b0;
            first_fetch_failed_q <= 1'b0;
          end
        end else if (can_pair) begin
          out_valid_q               <= 1'b1;
          out_inst1_q               <= first_instr_q;
          out_pc1_q                 <= first_pc_q;
          out_inst1_compressed_q    <= 1'b0;
          out_inst1_illegal_c_q     <= 1'b0;
          out_inst1_fetch_failed_q  <= first_fetch_failed_q;
          out_inst2_valid_q         <= 1'b1;
          out_inst2_q               <= in_instr_i;
          out_pc2_q                 <= in_pc_i;
          out_inst2_fetch_failed_q  <= in_fetch_failed_i;
          first_valid_q             <= 1'b0;
        end else begin
          // Discontinuity or non-pairable second instruction: emit the older
          // buffered instruction as a single and retain the incoming one.
          out_valid_q               <= 1'b1;
          out_inst1_q               <= first_instr_q;
          out_pc1_q                 <= first_pc_q;
          out_inst1_compressed_q    <= first_compressed_q;
          out_inst1_illegal_c_q     <= first_illegal_c_q;
          out_inst1_fetch_failed_q  <= first_fetch_failed_q;
          out_inst2_valid_q         <= 1'b0;

          first_valid_q        <= 1'b1;
          first_instr_q        <= in_instr_i;
          first_pc_q           <= in_pc_i;
          first_compressed_q   <= in_compressed_i;
          first_illegal_c_q    <= in_illegal_c_i;
          first_fetch_failed_q <= in_fetch_failed_i;
        end
      end else if (out_slot_free && first_valid_q &&
                   (first_compressed_q || first_illegal_c_q || first_fetch_failed_q)) begin
        // Serialize a retained compressed/faulting instruction.
        out_valid_q               <= 1'b1;
        out_inst1_q               <= first_instr_q;
        out_pc1_q                 <= first_pc_q;
        out_inst1_compressed_q    <= first_compressed_q;
        out_inst1_illegal_c_q     <= first_illegal_c_q;
        out_inst1_fetch_failed_q  <= first_fetch_failed_q;
        out_inst2_valid_q         <= 1'b0;
        first_valid_q             <= 1'b0;
      end
    end
  end

  assign out_valid_o               = out_valid_q;
  assign out_inst1_o               = out_inst1_q;
  assign out_pc1_o                 = out_pc1_q;
  assign out_inst1_compressed_o    = out_inst1_compressed_q;
  assign out_inst1_illegal_c_o     = out_inst1_illegal_c_q;
  assign out_inst1_fetch_failed_o  = out_inst1_fetch_failed_q;
  assign out_inst2_valid_o         = out_inst2_valid_q;
  assign out_inst2_o               = out_inst2_q;
  assign out_pc2_o                 = out_pc2_q;

endmodule
