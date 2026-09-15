// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.

module cv32e40p_sparv_prefetch_counters (
    input logic clk,
    input logic rst_n,
    input logic clear_i,

    input logic candidate_i,
    input logic issued_i,
    input logic filled_i,
    input logic useful_i,
    input logic wasted_i,
    input logic suppressed_i,
    input logic demand_miss_i,

    output logic [63:0] candidates_o,
    output logic [63:0] issued_o,
    output logic [63:0] filled_o,
    output logic [63:0] useful_o,
    output logic [63:0] wasted_o,
    output logic [63:0] suppressed_o,
    output logic [63:0] demand_misses_o
);

  function automatic logic [63:0] sat_inc(input logic [63:0] v, input logic en);
    sat_inc = (en && (&v == 1'b0)) ? (v + 64'd1) : v;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || clear_i) begin
      candidates_o    <= '0;
      issued_o        <= '0;
      filled_o        <= '0;
      useful_o        <= '0;
      wasted_o        <= '0;
      suppressed_o    <= '0;
      demand_misses_o <= '0;
    end else begin
      candidates_o    <= sat_inc(candidates_o, candidate_i);
      issued_o        <= sat_inc(issued_o, issued_i);
      filled_o        <= sat_inc(filled_o, filled_i);
      useful_o        <= sat_inc(useful_o, useful_i);
      wasted_o        <= sat_inc(wasted_o, wasted_i);
      suppressed_o    <= sat_inc(suppressed_o, suppressed_i);
      demand_misses_o <= sat_inc(demand_misses_o, demand_miss_i);
    end
  end

endmodule
