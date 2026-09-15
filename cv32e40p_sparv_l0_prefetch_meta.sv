// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Metadata shadow for the direct-mapped HAMSA/SPARV L0.  It records whether
// the currently resident line at each index arrived speculatively.  A demand
// hit to that exact prefetched line produces a one-cycle useful pulse and
// clears the bit so usefulness is counted once per prefetch fill.

module cv32e40p_sparv_l0_prefetch_meta #(
    parameter int LINES = 8
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        invalidate_i,

    input  logic        refill_valid_i,
    input  logic [31:0] refill_addr_i,
    input  logic        refill_prefetch_i,

    input  logic        demand_lookup_i,
    input  logic [31:0] demand_pc_i,
    input  logic        demand_hit_i,

    output logic        prefetch_useful_o,
    output logic        demand_hit_prefetched_o
);

  localparam int INDEX_W = $clog2(LINES);
  localparam int TAG_LSB = 4 + INDEX_W;

  logic [LINES-1:0] prefetched_q;
  logic [31-TAG_LSB:0] tag_q [LINES];
  logic [INDEX_W-1:0] refill_idx;
  logic [INDEX_W-1:0] lookup_idx;
  logic [31-TAG_LSB:0] refill_tag;
  logic [31-TAG_LSB:0] lookup_tag;
  integer i;

  assign refill_idx = refill_addr_i[4 +: INDEX_W];
  assign lookup_idx = demand_pc_i[4 +: INDEX_W];
  assign refill_tag = refill_addr_i[31:TAG_LSB];
  assign lookup_tag = demand_pc_i[31:TAG_LSB];

  assign demand_hit_prefetched_o = demand_lookup_i && demand_hit_i &&
                                    prefetched_q[lookup_idx] &&
                                    (tag_q[lookup_idx] == lookup_tag);
  assign prefetch_useful_o = demand_hit_prefetched_o;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prefetched_q <= '0;
      for (i = 0; i < LINES; i++) tag_q[i] <= '0;
    end else begin
      if (invalidate_i) prefetched_q <= '0;

      if (refill_valid_i) begin
        prefetched_q[refill_idx] <= refill_prefetch_i;
        tag_q[refill_idx]        <= refill_tag;
      end

      if (demand_hit_prefetched_o)
        prefetched_q[lookup_idx] <= 1'b0;
    end
  end

endmodule
