// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// SPARV next-line prefetch controller.
//
// This block is intentionally kept separate from the HAMSA-DI demand-refill
// path so SPARV can be brought up incrementally.  It observes architecturally
// useful demand accesses/refills and proposes the following 16-byte cache line
// as a low-priority prefetch target.  A demand miss always wins.  Redirects
// cancel speculative work so the prefetcher cannot perturb precise control
// flow.

module cv32e40p_sparv_prefetch_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    // Front-end control.
    input  logic        redirect_i,
    input  logic [31:0] redirect_pc_i,

    // Demand-side observation. Addresses may be byte PCs; this block aligns
    // them to the 16-byte L0 line used by the HAMSA-DI H2 frontend.
    input  logic        demand_lookup_i,
    input  logic [31:0] demand_pc_i,
    input  logic        demand_hit_i,
    input  logic        demand_miss_i,

    // Asserted when a demand refill commits into the L0.
    input  logic        demand_refill_i,
    input  logic [31:0] demand_refill_addr_i,

    // Back-pressure / arbitration from the shared refill path.
    input  logic        refill_busy_i,
    input  logic        prefetch_accept_i,

    // Low-priority prefetch request.
    output logic        prefetch_valid_o,
    output logic [31:0] prefetch_addr_o,

    // Instrumentation.
    output logic        prefetch_candidate_o,
    output logic        prefetch_suppressed_o
);

  logic        candidate_valid_q;
  logic [31:0] candidate_addr_q;

  function automatic logic [31:0] line_base(input logic [31:0] addr);
    line_base = {addr[31:4], 4'b0000};
  endfunction

  function automatic logic [31:0] next_line(input logic [31:0] addr);
    next_line = line_base(addr) + 32'd16;
  endfunction

  // The latest useful demand access defines the next sequential line.  A
  // completed refill is preferred because it proves the current line exists
  // in L0. Hits also train the candidate, which supports streaming execution
  // without waiting for another miss.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      candidate_valid_q <= 1'b0;
      candidate_addr_q  <= 32'd0;
    end else begin
      if (redirect_i) begin
        candidate_valid_q <= 1'b1;
        candidate_addr_q  <= next_line(redirect_pc_i);
      end else begin
        if (demand_refill_i) begin
          candidate_valid_q <= 1'b1;
          candidate_addr_q  <= next_line(demand_refill_addr_i);
        end else if (demand_lookup_i && demand_hit_i) begin
          candidate_valid_q <= 1'b1;
          candidate_addr_q  <= next_line(demand_pc_i);
        end

        if (prefetch_valid_o && prefetch_accept_i)
          candidate_valid_q <= 1'b0;
      end
    end
  end

  // Demand misses have strict priority.  The shared refill engine may also
  // suppress the speculative request while occupied.
  assign prefetch_valid_o      = candidate_valid_q && !redirect_i &&
                                 !demand_miss_i && !refill_busy_i;
  assign prefetch_addr_o       = candidate_addr_q;
  assign prefetch_candidate_o  = candidate_valid_q;
  assign prefetch_suppressed_o = candidate_valid_q &&
                                 (redirect_i || demand_miss_i || refill_busy_i);

endmodule
