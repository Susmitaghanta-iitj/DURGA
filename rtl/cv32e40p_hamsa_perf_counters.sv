// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Lightweight counters for evaluating the HAMSA-DI prototype. These counters
// are intentionally separate from architectural mhpmcounter CSRs so the core
// can be characterized without changing the privileged-visible CSR map.

module cv32e40p_hamsa_perf_counters (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clear_i,
    input  logic        cycle_i,
    input  logic        issue1_retire_i,
    input  logic        issue2_issue_i,
    input  logic        issue2_retire_i,
    input  logic        issue2_blocked_i,
    input  logic        issue2_killed_i,
    input  logic        l0_lookup_i,
    input  logic        l0_hit_i,

    output logic [63:0] cycles_o,
    output logic [63:0] issue1_retired_o,
    output logic [63:0] issue2_issued_o,
    output logic [63:0] issue2_retired_o,
    output logic [63:0] issue2_blocked_o,
    output logic [63:0] issue2_killed_o,
    output logic [63:0] l0_lookups_o,
    output logic [63:0] l0_hits_o
);

  function automatic logic [63:0] inc_sat(input logic [63:0] value);
    inc_sat = (&value) ? value : value + 64'd1;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycles_o          <= '0;
      issue1_retired_o  <= '0;
      issue2_issued_o   <= '0;
      issue2_retired_o  <= '0;
      issue2_blocked_o  <= '0;
      issue2_killed_o   <= '0;
      l0_lookups_o      <= '0;
      l0_hits_o         <= '0;
    end else if (clear_i) begin
      cycles_o          <= '0;
      issue1_retired_o  <= '0;
      issue2_issued_o   <= '0;
      issue2_retired_o  <= '0;
      issue2_blocked_o  <= '0;
      issue2_killed_o   <= '0;
      l0_lookups_o      <= '0;
      l0_hits_o         <= '0;
    end else begin
      if (cycle_i)          cycles_o         <= inc_sat(cycles_o);
      if (issue1_retire_i)  issue1_retired_o <= inc_sat(issue1_retired_o);
      if (issue2_issue_i)   issue2_issued_o  <= inc_sat(issue2_issued_o);
      if (issue2_retire_i)  issue2_retired_o <= inc_sat(issue2_retired_o);
      if (issue2_blocked_i) issue2_blocked_o <= inc_sat(issue2_blocked_o);
      if (issue2_killed_i)  issue2_killed_o  <= inc_sat(issue2_killed_o);
      if (l0_lookup_i)      l0_lookups_o     <= inc_sat(l0_lookups_o);
      if (l0_lookup_i && l0_hit_i)
        l0_hits_o <= inc_sat(l0_hits_o);
    end
  end

endmodule
