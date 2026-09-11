// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Direct-mapped 8-line x 128-bit L0 instruction cache prototype inspired by
// HAMSA-DI. This block is intentionally protocol-agnostic: an external refill
// engine supplies complete 128-bit lines. It provides two 32-bit words per
// lookup for the fixed-width dual-issue frontend milestone.

module cv32e40p_l0_icache_128 #(
    parameter int LINES = 8
) (
    input logic clk,
    input logic rst_n,

    input logic        invalidate_i,

    input  logic        lookup_valid_i,
    input  logic [31:0] lookup_pc_i,
    output logic        lookup_hit_o,
    output logic [31:0] inst1_o,
    output logic [31:0] inst2_o,
    output logic        inst2_same_line_o,

    input logic         refill_valid_i,
    input logic [31:0]  refill_addr_i,
    input logic [127:0] refill_data_i
);

  localparam int INDEX_W = $clog2(LINES);
  localparam int TAG_LSB = 4 + INDEX_W;

  logic [LINES-1:0] valid_q;
  logic [31-TAG_LSB:0] tag_q [LINES];
  logic [127:0] data_q [LINES];

  logic [INDEX_W-1:0] lookup_idx;
  logic [INDEX_W-1:0] refill_idx;
  logic [31-TAG_LSB:0] lookup_tag;
  logic [31-TAG_LSB:0] refill_tag;
  logic [1:0] word_sel;
  integer i;

  assign lookup_idx = lookup_pc_i[4 +: INDEX_W];
  assign refill_idx = refill_addr_i[4 +: INDEX_W];
  assign lookup_tag = lookup_pc_i[31:TAG_LSB];
  assign refill_tag = refill_addr_i[31:TAG_LSB];
  assign word_sel   = lookup_pc_i[3:2];

  assign lookup_hit_o = lookup_valid_i && valid_q[lookup_idx] &&
                        (tag_q[lookup_idx] == lookup_tag);

  always_comb begin
    inst1_o           = 32'd0;
    inst2_o           = 32'd0;
    inst2_same_line_o = 1'b0;

    unique case (word_sel)
      2'd0: begin
        inst1_o           = data_q[lookup_idx][31:0];
        inst2_o           = data_q[lookup_idx][63:32];
        inst2_same_line_o = 1'b1;
      end
      2'd1: begin
        inst1_o           = data_q[lookup_idx][63:32];
        inst2_o           = data_q[lookup_idx][95:64];
        inst2_same_line_o = 1'b1;
      end
      2'd2: begin
        inst1_o           = data_q[lookup_idx][95:64];
        inst2_o           = data_q[lookup_idx][127:96];
        inst2_same_line_o = 1'b1;
      end
      default: begin
        inst1_o           = data_q[lookup_idx][127:96];
        inst2_o           = 32'd0;
        inst2_same_line_o = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q <= '0;
      for (i = 0; i < LINES; i++) begin
        tag_q[i]  <= '0;
        data_q[i] <= '0;
      end
    end else begin
      if (invalidate_i) valid_q <= '0;
      if (refill_valid_i) begin
        valid_q[refill_idx] <= 1'b1;
        tag_q[refill_idx]   <= refill_tag;
        data_q[refill_idx]  <= refill_data_i;
      end
    end
  end

endmodule
