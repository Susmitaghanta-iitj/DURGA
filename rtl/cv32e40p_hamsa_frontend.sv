// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// HAMSA-DI style frontend prototype for CV32E40P.
// - 8 x 128-bit direct-mapped L0 instruction cache
// - RV32C-aware extraction of up to two instructions per lookup
// - decompression through the existing CV32E40P compressed decoder
// - redirect/invalidate support
//
// The refill interface is intentionally simple: an external refill engine
// provides a complete 128-bit line. This keeps the frontend independent of a
// particular bus adapter while preserving the HAMSA-DI organization.

module cv32e40p_hamsa_frontend #(
    parameter int LINES = 8,
    parameter int FPU   = 0
) (
    input  logic         clk,
    input  logic         rst_n,

    input  logic         invalidate_i,
    input  logic         redirect_i,
    input  logic [31:0]  redirect_pc_i,

    input  logic         lookup_valid_i,
    input  logic [31:0]  lookup_pc_i,
    output logic         lookup_ready_o,
    output logic         lookup_hit_o,

    input  logic         refill_valid_i,
    input  logic [31:0]  refill_addr_i,
    input  logic [127:0] refill_data_i,

    output logic         pair_valid_o,
    input  logic         pair_ready_i,

    output logic [31:0]  inst1_o,
    output logic [31:0]  pc1_o,
    output logic         inst1_compressed_o,
    output logic         inst1_illegal_c_o,

    output logic         inst2_valid_o,
    output logic [31:0]  inst2_o,
    output logic [31:0]  pc2_o,
    output logic         inst2_compressed_o,
    output logic         inst2_illegal_c_o,

    output logic [31:0]  next_pc_o
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
  logic [127:0] lookup_line;
  logic [2:0] halfword_index;

  logic dec1_valid;
  logic dec2_valid;
  logic [2:0] dec1_halfwords;
  logic [2:0] dec2_halfwords;
  logic [31:0] dec1;
  logic [31:0] dec2;
  logic dec1_c;
  logic dec2_c;
  logic dec1_illegal;
  logic dec2_illegal;

  logic pair_valid_q;
  logic [31:0] inst1_q;
  logic [31:0] pc1_q;
  logic inst1_c_q;
  logic inst1_illegal_q;
  logic inst2_valid_q;
  logic [31:0] inst2_q;
  logic [31:0] pc2_q;
  logic inst2_c_q;
  logic inst2_illegal_q;
  logic [31:0] next_pc_q;

  integer i;

  assign lookup_idx     = lookup_pc_i[4 +: INDEX_W];
  assign refill_idx     = refill_addr_i[4 +: INDEX_W];
  assign lookup_tag     = lookup_pc_i[31:TAG_LSB];
  assign refill_tag     = refill_addr_i[31:TAG_LSB];
  assign halfword_index = lookup_pc_i[3:1];
  assign lookup_line    = data_q[lookup_idx];

  assign lookup_hit_o = lookup_valid_i && valid_q[lookup_idx] &&
                        (tag_q[lookup_idx] == lookup_tag);

  // A one-entry output register decouples cache lookup from decode/issue.
  assign lookup_ready_o = !pair_valid_q || pair_ready_i;

  cv32e40p_dual_decode_128 #(
      .FPU(FPU)
  ) dual_decode_i (
      .line_i              (lookup_line),
      .halfword_index_i    (halfword_index),
      .line_valid_i        (lookup_hit_o),
      .inst1_valid_o       (dec1_valid),
      .inst1_o             (dec1),
      .inst1_compressed_o  (dec1_c),
      .inst1_illegal_c_o   (dec1_illegal),
      .inst1_halfwords_o   (dec1_halfwords),
      .inst2_valid_o       (dec2_valid),
      .inst2_o             (dec2),
      .inst2_compressed_o  (dec2_c),
      .inst2_illegal_c_o   (dec2_illegal),
      .inst2_halfwords_o   (dec2_halfwords)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q          <= '0;
      pair_valid_q     <= 1'b0;
      inst1_q          <= '0;
      pc1_q            <= '0;
      inst1_c_q        <= 1'b0;
      inst1_illegal_q  <= 1'b0;
      inst2_valid_q    <= 1'b0;
      inst2_q          <= '0;
      pc2_q            <= '0;
      inst2_c_q        <= 1'b0;
      inst2_illegal_q  <= 1'b0;
      next_pc_q        <= '0;
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

      if (redirect_i) begin
        pair_valid_q <= 1'b0;
        next_pc_q    <= redirect_pc_i;
      end else begin
        if (pair_valid_q && pair_ready_i)
          pair_valid_q <= 1'b0;

        if (lookup_valid_i && lookup_ready_o && lookup_hit_o && dec1_valid) begin
          pair_valid_q    <= 1'b1;
          inst1_q         <= dec1;
          pc1_q           <= lookup_pc_i;
          inst1_c_q       <= dec1_c;
          inst1_illegal_q <= dec1_illegal;

          inst2_valid_q   <= dec2_valid && !dec1_illegal;
          inst2_q         <= dec2;
          pc2_q           <= lookup_pc_i + {28'd0, dec1_halfwords, 1'b0};
          inst2_c_q       <= dec2_c;
          inst2_illegal_q <= dec2_illegal;

          if (dec2_valid && !dec1_illegal && !dec2_illegal)
            next_pc_q <= lookup_pc_i + {27'd0, (dec1_halfwords + dec2_halfwords), 1'b0};
          else
            next_pc_q <= lookup_pc_i + {28'd0, dec1_halfwords, 1'b0};
        end
      end
    end
  end

  assign pair_valid_o        = pair_valid_q;
  assign inst1_o             = inst1_q;
  assign pc1_o               = pc1_q;
  assign inst1_compressed_o  = inst1_c_q;
  assign inst1_illegal_c_o   = inst1_illegal_q;
  assign inst2_valid_o       = inst2_valid_q;
  assign inst2_o             = inst2_q;
  assign pc2_o               = pc2_q;
  assign inst2_compressed_o  = inst2_c_q;
  assign inst2_illegal_c_o   = inst2_illegal_q;
  assign next_pc_o           = next_pc_q;

endmodule
