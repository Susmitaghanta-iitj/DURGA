// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// SPARV shared refill-source arbiter. Architectural demand misses have strict
// priority over speculative next-line prefetches. The selected source is
// latched on request acceptance so a later refill completion can be classified
// without relying on combinational request state.

module cv32e40p_sparv_refill_arbiter (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,

    input  logic        demand_valid_i,
    input  logic [31:0] demand_addr_i,

    input  logic        prefetch_valid_i,
    input  logic [31:0] prefetch_addr_i,
    input  logic        prefetch_cached_i,

    output logic        refill_req_valid_o,
    output logic [31:0] refill_req_addr_o,
    input  logic        refill_req_ready_i,
    input  logic        refill_complete_i,

    output logic        demand_accept_o,
    output logic        prefetch_accept_o,
    output logic        refill_is_prefetch_o
);

  logic active_is_prefetch_q;
  logic active_valid_q;
  logic select_prefetch;

  assign select_prefetch = !demand_valid_i && prefetch_valid_i && !prefetch_cached_i;

  always_comb begin
    refill_req_valid_o = demand_valid_i || select_prefetch;
    refill_req_addr_o  = demand_valid_i ? demand_addr_i : prefetch_addr_i;

    demand_accept_o   = refill_req_valid_o && refill_req_ready_i && demand_valid_i;
    prefetch_accept_o = refill_req_valid_o && refill_req_ready_i && select_prefetch;

    // Completion classification is valid only while an accepted transaction is
    // outstanding. The refill engines are single-outstanding by construction.
    refill_is_prefetch_o = refill_complete_i && active_valid_q && active_is_prefetch_q;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_valid_q       <= 1'b0;
      active_is_prefetch_q <= 1'b0;
    end else if (flush_i) begin
      active_valid_q       <= 1'b0;
      active_is_prefetch_q <= 1'b0;
    end else begin
      if (demand_accept_o) begin
        active_valid_q       <= 1'b1;
        active_is_prefetch_q <= 1'b0;
      end else if (prefetch_accept_o) begin
        active_valid_q       <= 1'b1;
        active_is_prefetch_q <= 1'b1;
      end

      if (refill_complete_i)
        active_valid_q <= 1'b0;
    end
  end

endmodule
