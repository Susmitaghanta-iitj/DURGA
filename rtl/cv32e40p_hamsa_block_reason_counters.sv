// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Evaluation-only counters for classifying lost Issue2 opportunities.
// Reasons are intentionally allowed to overlap; e.g. a candidate may be both
// RAW-hazardous and unsupported. The aggregate blocked counter therefore need
// not equal the sum of reason counters.

module cv32e40p_hamsa_block_reason_counters (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clear_i,
    input  logic        blocked_i,
    input  logic        raw_i,
    input  logic        waw_i,
    input  logic        unsupported_i,
    input  logic        serializing_i,
    input  logic        busy_i,
    input  logic        decode_i,

    output logic [63:0] blocked_o,
    output logic [63:0] raw_o,
    output logic [63:0] waw_o,
    output logic [63:0] unsupported_o,
    output logic [63:0] serializing_o,
    output logic [63:0] busy_o,
    output logic [63:0] decode_o
);

  function automatic logic [63:0] inc_sat(input logic [63:0] value);
    inc_sat = (&value) ? value : value + 64'd1;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      blocked_o     <= '0;
      raw_o         <= '0;
      waw_o         <= '0;
      unsupported_o <= '0;
      serializing_o <= '0;
      busy_o        <= '0;
      decode_o      <= '0;
    end else if (clear_i) begin
      blocked_o     <= '0;
      raw_o         <= '0;
      waw_o         <= '0;
      unsupported_o <= '0;
      serializing_o <= '0;
      busy_o        <= '0;
      decode_o      <= '0;
    end else begin
      if (blocked_i)     blocked_o     <= inc_sat(blocked_o);
      if (blocked_i && raw_i)         raw_o         <= inc_sat(raw_o);
      if (blocked_i && waw_i)         waw_o         <= inc_sat(waw_o);
      if (blocked_i && unsupported_i) unsupported_o <= inc_sat(unsupported_o);
      if (blocked_i && serializing_i) serializing_o <= inc_sat(serializing_o);
      if (blocked_i && busy_i)        busy_o        <= inc_sat(busy_o);
      if (blocked_i && decode_i)      decode_o      <= inc_sat(decode_o);
    end
  end

endmodule
