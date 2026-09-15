// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Shadow metadata directory for the SPARV L0 prefetch path. The HAMSA L0 is
// direct-mapped and line-sized at 16 bytes; this block mirrors only tag/valid
// state plus a "prefetched but not yet demanded" bit. It provides a probe port
// for suppressing redundant next-line requests and produces useful/wasted
// prefetch events for evaluation.

module cv32e40p_sparv_prefetch_directory #(
    parameter int LINES = 8
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        invalidate_i,

    input  logic        refill_valid_i,
    input  logic [31:0] refill_addr_i,
    input  logic        refill_is_prefetch_i,

    input  logic        demand_lookup_i,
    input  logic [31:0] demand_pc_i,
    input  logic        demand_hit_i,

    input  logic [31:0] probe_addr_i,
    output logic        probe_hit_o,

    output logic        useful_prefetch_o,
    output logic        wasted_prefetch_o
);

  localparam int INDEX_W = (LINES <= 1) ? 1 : $clog2(LINES);
  localparam int INDEX_LSB = 4;
  localparam int TAG_LSB = INDEX_LSB + INDEX_W;
  localparam int TAG_W = 32 - TAG_LSB;

  logic [LINES-1:0] valid_q;
  logic [LINES-1:0] prefetched_q;
  logic [TAG_W-1:0] tag_q [LINES];

  logic [INDEX_W-1:0] probe_idx;
  logic [TAG_W-1:0] probe_tag;
  logic [INDEX_W-1:0] demand_idx;
  logic [TAG_W-1:0] demand_tag;
  logic [INDEX_W-1:0] refill_idx;
  logic [TAG_W-1:0] refill_tag;

  integer i;

  assign probe_idx = probe_addr_i[INDEX_LSB +: INDEX_W];
  assign probe_tag = probe_addr_i[31:TAG_LSB];
  assign demand_idx = demand_pc_i[INDEX_LSB +: INDEX_W];
  assign demand_tag = demand_pc_i[31:TAG_LSB];
  assign refill_idx = refill_addr_i[INDEX_LSB +: INDEX_W];
  assign refill_tag = refill_addr_i[31:TAG_LSB];

  assign probe_hit_o = valid_q[probe_idx] && (tag_q[probe_idx] == probe_tag);

  always_comb begin
    useful_prefetch_o = 1'b0;
    wasted_prefetch_o = 1'b0;

    if (demand_lookup_i && demand_hit_i && valid_q[demand_idx] &&
        (tag_q[demand_idx] == demand_tag) && prefetched_q[demand_idx])
      useful_prefetch_o = 1'b1;

    if (refill_valid_i && valid_q[refill_idx] && prefetched_q[refill_idx] &&
        (tag_q[refill_idx] != refill_tag))
      wasted_prefetch_o = 1'b1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q      <= '0;
      prefetched_q <= '0;
      for (i = 0; i < LINES; i = i + 1)
        tag_q[i] <= '0;
    end else if (invalidate_i) begin
      // Fence/architectural invalidation is not counted as a replacement
      // waste event; the evaluation counter tracks normal cache pollution.
      valid_q      <= '0;
      prefetched_q <= '0;
    end else begin
      if (demand_lookup_i && demand_hit_i && valid_q[demand_idx] &&
          (tag_q[demand_idx] == demand_tag) && prefetched_q[demand_idx])
        prefetched_q[demand_idx] <= 1'b0;

      if (refill_valid_i) begin
        valid_q[refill_idx]      <= 1'b1;
        tag_q[refill_idx]        <= refill_tag;
        prefetched_q[refill_idx] <= refill_is_prefetch_i;
      end
    end
  end

endmodule
