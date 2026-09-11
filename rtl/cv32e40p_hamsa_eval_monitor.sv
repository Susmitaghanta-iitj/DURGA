// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Evaluation-only monitor that combines the general HAMSA-DI performance
// counters with detailed Issue2 block-reason counters. This module is intended
// for simulation/FPGA characterization and is not part of the architectural CSR
// state. Testbenches may read the outputs hierarchically or expose them through
// a debug/status wrapper.

module cv32e40p_hamsa_eval_monitor (
    input logic clk,
    input logic rst_n,
    input logic clear_i,

    input logic cycle_i,
    input logic issue1_retire_i,
    input logic issue2_issue_i,
    input logic issue2_retire_i,
    input logic issue2_blocked_i,
    input logic issue2_killed_i,
    input logic l0_lookup_i,
    input logic l0_hit_i,

    input logic block_raw_i,
    input logic block_waw_i,
    input logic block_unsupported_i,
    input logic block_serializing_i,
    input logic block_busy_i,
    input logic block_decode_i,

    output logic [63:0] cycles_o,
    output logic [63:0] issue1_retired_o,
    output logic [63:0] issue2_issued_o,
    output logic [63:0] issue2_retired_o,
    output logic [63:0] issue2_blocked_o,
    output logic [63:0] issue2_killed_o,
    output logic [63:0] l0_lookups_o,
    output logic [63:0] l0_hits_o,

    output logic [63:0] block_raw_o,
    output logic [63:0] block_waw_o,
    output logic [63:0] block_unsupported_o,
    output logic [63:0] block_serializing_o,
    output logic [63:0] block_busy_o,
    output logic [63:0] block_decode_o
);

  logic [63:0] reason_blocked_unused;

  cv32e40p_hamsa_perf_counters perf_i (
      .clk              (clk),
      .rst_n            (rst_n),
      .clear_i          (clear_i),
      .cycle_i          (cycle_i),
      .issue1_retire_i  (issue1_retire_i),
      .issue2_issue_i   (issue2_issue_i),
      .issue2_retire_i  (issue2_retire_i),
      .issue2_blocked_i (issue2_blocked_i),
      .issue2_killed_i  (issue2_killed_i),
      .l0_lookup_i      (l0_lookup_i),
      .l0_hit_i         (l0_hit_i),
      .cycles_o         (cycles_o),
      .issue1_retired_o (issue1_retired_o),
      .issue2_issued_o  (issue2_issued_o),
      .issue2_retired_o (issue2_retired_o),
      .issue2_blocked_o (issue2_blocked_o),
      .issue2_killed_o  (issue2_killed_o),
      .l0_lookups_o     (l0_lookups_o),
      .l0_hits_o        (l0_hits_o)
  );

  cv32e40p_hamsa_block_reason_counters block_i (
      .clk           (clk),
      .rst_n         (rst_n),
      .clear_i       (clear_i),
      .blocked_i     (issue2_blocked_i),
      .raw_i         (block_raw_i),
      .waw_i         (block_waw_i),
      .unsupported_i (block_unsupported_i),
      .serializing_i (block_serializing_i),
      .busy_i        (block_busy_i),
      .decode_i      (block_decode_i),
      .blocked_o     (reason_blocked_unused),
      .raw_o         (block_raw_o),
      .waw_o         (block_waw_o),
      .unsupported_o (block_unsupported_o),
      .serializing_o (block_serializing_o),
      .busy_o        (block_busy_o),
      .decode_o      (block_decode_o)
  );

endmodule
