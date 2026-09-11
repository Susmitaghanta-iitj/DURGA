`timescale 1ns/1ps

module cv32e40p_dual_fetch_pair_buffer_tb;
  logic clk = 0;
  logic rst_n = 0;
  logic flush;
  logic in_valid;
  logic [31:0] in_instr;
  logic [31:0] in_pc;
  logic in_compressed;
  logic in_illegal_c;
  logic in_fetch_failed;
  logic in_ready;
  logic out_valid;
  logic [31:0] out_inst1;
  logic [31:0] out_pc1;
  logic out_inst1_compressed;
  logic out_inst1_illegal_c;
  logic out_inst1_fetch_failed;
  logic out_inst2_valid;
  logic [31:0] out_inst2;
  logic [31:0] out_pc2;
  logic out_ready;
  logic out_inst2_consumed;

  always #5 clk = ~clk;

  cv32e40p_dual_fetch_pair_buffer dut (
      .clk(clk), .rst_n(rst_n), .flush_i(flush),
      .in_valid_i(in_valid), .in_instr_i(in_instr), .in_pc_i(in_pc),
      .in_compressed_i(in_compressed), .in_illegal_c_i(in_illegal_c),
      .in_fetch_failed_i(in_fetch_failed), .in_ready_o(in_ready),
      .out_valid_o(out_valid), .out_inst1_o(out_inst1), .out_pc1_o(out_pc1),
      .out_inst1_compressed_o(out_inst1_compressed),
      .out_inst1_illegal_c_o(out_inst1_illegal_c),
      .out_inst1_fetch_failed_o(out_inst1_fetch_failed),
      .out_inst2_valid_o(out_inst2_valid), .out_inst2_o(out_inst2),
      .out_pc2_o(out_pc2), .out_ready_i(out_ready),
      .out_inst2_consumed_i(out_inst2_consumed)
  );

  task automatic send(
      input logic [31:0] instr,
      input logic [31:0] pc,
      input logic compressed,
      input logic illegal_c,
      input logic fetch_failed
  );
    begin
      while (!in_ready) @(posedge clk);
      in_instr <= instr;
      in_pc <= pc;
      in_compressed <= compressed;
      in_illegal_c <= illegal_c;
      in_fetch_failed <= fetch_failed;
      in_valid <= 1'b1;
      @(posedge clk);
      in_valid <= 1'b0;
    end
  endtask

  initial begin
    flush = 0;
    in_valid = 0;
    in_instr = 0;
    in_pc = 0;
    in_compressed = 0;
    in_illegal_c = 0;
    in_fetch_failed = 0;
    out_ready = 0;
    out_inst2_consumed = 0;

    repeat (3) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    send(32'h0010_0093, 32'h1000, 1'b0, 1'b0, 1'b0);
    send(32'h0020_0113, 32'h1004, 1'b0, 1'b0, 1'b0);

    while (!out_valid) @(posedge clk);
    if (!out_inst2_valid || out_inst1 !== 32'h0010_0093 ||
        out_inst2 !== 32'h0020_0113) begin
      $error("Expected a two-instruction pair");
      $fatal(1);
    end

    // Consume only instruction 1. Instruction 2 must be replayed.
    out_inst2_consumed <= 1'b0;
    out_ready <= 1'b1;
    @(posedge clk);
    out_ready <= 1'b0;

    // Supply a discontinuous instruction so the replayed instruction is emitted
    // as a single instead of being paired with it.
    send(32'h0030_0193, 32'h1010, 1'b0, 1'b0, 1'b0);
    while (!out_valid) @(posedge clk);
    if (out_inst1 !== 32'h0020_0113 || out_pc1 !== 32'h1004 || out_inst2_valid) begin
      $error("Blocked Issue2 instruction was not replayed as next Issue1");
      $fatal(1);
    end
    out_ready <= 1'b1;
    @(posedge clk);
    out_ready <= 1'b0;

    // The discontinuous instruction is now retained as the next Issue1. Feed a
    // compressed instruction; the retained normal instruction must retire first.
    send(32'h0000_0001, 32'h2000, 1'b1, 1'b1, 1'b0);
    while (!out_valid) @(posedge clk);
    if (out_inst1 !== 32'h0030_0193 || out_pc1 !== 32'h1010 || out_inst2_valid) begin
      $error("Retained discontinuous instruction did not retire before compressed input");
      $fatal(1);
    end
    out_ready <= 1'b1;
    @(posedge clk);
    out_ready <= 1'b0;

    // The sequential block replaces the just-consumed output in the NBA region.
    // Sample after the falling edge so we cannot accidentally re-read the stale
    // discontinuous output from the same active clock edge.
    @(negedge clk);

    // The retained compressed instruction must then serialize with its metadata
    // intact.
    while (!out_valid) @(posedge clk);
    if (out_inst1 !== 32'h0000_0001 || out_pc1 !== 32'h2000 ||
        !out_inst1_compressed || !out_inst1_illegal_c || out_inst1_fetch_failed) begin
      $error("Compressed/illegal metadata was not preserved");
      $fatal(1);
    end

    $display("cv32e40p_dual_fetch_pair_buffer_tb: PASS");
    $finish;
  end
endmodule
