// Directed test for the dual-fetch pair buffer replay contract.

module cv32e40p_dual_fetch_pair_buffer_tb;
  logic clk;
  logic rst_n;
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

  cv32e40p_dual_fetch_pair_buffer dut (
      .clk                      (clk),
      .rst_n                    (rst_n),
      .flush_i                  (flush),
      .in_valid_i               (in_valid),
      .in_instr_i               (in_instr),
      .in_pc_i                  (in_pc),
      .in_compressed_i          (in_compressed),
      .in_illegal_c_i           (in_illegal_c),
      .in_fetch_failed_i        (in_fetch_failed),
      .in_ready_o               (in_ready),
      .out_valid_o              (out_valid),
      .out_inst1_o              (out_inst1),
      .out_pc1_o                (out_pc1),
      .out_inst1_compressed_o   (out_inst1_compressed),
      .out_inst1_illegal_c_o    (out_inst1_illegal_c),
      .out_inst1_fetch_failed_o (out_inst1_fetch_failed),
      .out_inst2_valid_o        (out_inst2_valid),
      .out_inst2_o              (out_inst2),
      .out_pc2_o                (out_pc2),
      .out_ready_i              (out_ready),
      .out_inst2_consumed_i     (out_inst2_consumed)
  );

  always #5 clk = ~clk;

  task automatic send(
      input logic [31:0] insn,
      input logic [31:0] pc,
      input logic comp,
      input logic ill,
      input logic fault
  );
    begin
      while (!in_ready) @(posedge clk);
      in_instr        <= insn;
      in_pc           <= pc;
      in_compressed   <= comp;
      in_illegal_c    <= ill;
      in_fetch_failed <= fault;
      in_valid        <= 1'b1;
      @(posedge clk);
      in_valid        <= 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    flush = 1'b0;
    in_valid = 1'b0;
    in_instr = '0;
    in_pc = '0;
    in_compressed = 1'b0;
    in_illegal_c = 1'b0;
    in_fetch_failed = 1'b0;
    out_ready = 1'b0;
    out_inst2_consumed = 1'b0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // Pair two sequential 32-bit instructions.
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

    // Compressed/fault metadata is preserved on serialized instructions.
    send(32'h0000_0001, 32'h2000, 1'b1, 1'b1, 1'b0);
    while (!out_valid) @(posedge clk);
    if (!out_inst1_compressed || !out_inst1_illegal_c || out_inst1_fetch_failed) begin
      $error("Compressed/illegal metadata was not preserved");
      $fatal(1);
    end

    $display("cv32e40p_dual_fetch_pair_buffer_tb: PASS");
    $finish;
  end
endmodule
