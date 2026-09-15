// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// SPARV MAC/DOTP accelerator lane.
//
// This block intentionally consumes decoded micro-operations rather than raw
// instructions. The public SPARV paper identifies pv.dot* style operations but
// does not define the complete custom encoding table. Keeping decode outside
// this lane avoids inventing an incompatible ISA while allowing the execution,
// kill and in-order writeback behavior to be integrated and verified now.

module cv32e40p_sparv_accel_lane (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        kill_i,

    input  logic        op_valid_i,
    output logic        op_ready_o,
    input  logic [4:0]  rd_i,
    input  logic [31:0] operand_a_i,
    input  logic [31:0] operand_b_i,
    input  logic [63:0] accumulator_i,
    input  logic [1:0]  simd_mode_i,
    input  logic        signed_a_i,
    input  logic        signed_b_i,
    input  logic        accumulate_i,

    // Commit permission is provided by the in-order core once all older
    // operations are known to be non-faulting/retired.
    input  logic        commit_safe_i,

    output logic        wb_valid_o,
    input  logic        wb_ready_i,
    output logic [4:0]  wb_rd_o,
    output logic [63:0] wb_data_o,
    output logic        busy_o
);

  logic engine_ready;
  logic engine_result_valid;
  logic engine_result_ready;
  logic [63:0] engine_result;
  logic engine_busy;
  logic [4:0] rd_q;

  assign op_ready_o          = engine_ready;
  assign engine_result_ready = commit_safe_i && wb_ready_i;
  assign wb_valid_o          = engine_result_valid && commit_safe_i;
  assign wb_rd_o             = rd_q;
  assign wb_data_o           = engine_result;
  assign busy_o              = engine_busy;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rd_q <= '0;
    else if (kill_i)
      rd_q <= '0;
    else if (op_valid_i && op_ready_o)
      rd_q <= rd_i;
  end

  cv32e40p_sparv_mac_dotp_engine engine_i (
      .clk            (clk),
      .rst_n          (rst_n),
      .kill_i         (kill_i),
      .valid_i        (op_valid_i),
      .ready_o        (engine_ready),
      .operand_a_i    (operand_a_i),
      .operand_b_i    (operand_b_i),
      .accumulator_i  (accumulator_i),
      .simd_mode_i    (simd_mode_i),
      .signed_a_i     (signed_a_i),
      .signed_b_i     (signed_b_i),
      .accumulate_i   (accumulate_i),
      .result_valid_o (engine_result_valid),
      .result_ready_i (engine_result_ready),
      .result_o       (engine_result),
      .busy_o         (engine_busy)
  );

endmodule
