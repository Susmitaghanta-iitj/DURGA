`timescale 1ns/1ps

module cv32e40p_sparv_mac_dotp_engine_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic kill_i, valid_i, ready_o;
  logic [31:0] operand_a_i, operand_b_i;
  logic [63:0] accumulator_i;
  logic [1:0] simd_mode_i;
  logic signed_a_i, signed_b_i, accumulate_i;
  logic result_valid_o, result_ready_i, busy_o;
  logic [63:0] result_o;

  always #5 clk = ~clk;

  cv32e40p_sparv_mac_dotp_engine dut (.*);

  task automatic clear_inputs;
    begin
      kill_i         = 1'b0;
      valid_i        = 1'b0;
      operand_a_i    = '0;
      operand_b_i    = '0;
      accumulator_i  = '0;
      simd_mode_i    = 2'b00;
      signed_a_i     = 1'b0;
      signed_b_i     = 1'b0;
      accumulate_i   = 1'b0;
      result_ready_i = 1'b0;
    end
  endtask

  task automatic check(input logic cond, input string msg);
    if (!cond) begin
      $display("FAIL: %s", msg);
      $fatal(1);
    end
  endtask

  task automatic launch_and_check(
      input logic [1:0] mode,
      input logic [31:0] a,
      input logic [31:0] b,
      input logic [63:0] acc,
      input logic sa,
      input logic sb,
      input logic do_acc,
      input logic [63:0] expected,
      input integer latency
  );
    integer c;
    begin
      @(negedge clk);
      simd_mode_i   = mode;
      operand_a_i   = a;
      operand_b_i   = b;
      accumulator_i = acc;
      signed_a_i    = sa;
      signed_b_i    = sb;
      accumulate_i  = do_acc;
      valid_i       = 1'b1;
      check(ready_o, "engine must be ready before launch");
      @(posedge clk);
      #1;
      valid_i = 1'b0;
      check(busy_o, "engine must become busy");

      for (c = 1; c < latency; c = c + 1) begin
        check(!result_valid_o, "result asserted too early");
        @(posedge clk);
        #1;
      end
      check(result_valid_o, "result did not arrive at expected latency");
      check(result_o === expected, "result mismatch");

      // Hold result under backpressure.
      @(posedge clk);
      #1;
      check(result_valid_o, "result must remain valid under backpressure");
      check(result_o === expected, "held result changed");

      result_ready_i = 1'b1;
      @(posedge clk);
      #1;
      result_ready_i = 1'b0;
      check(ready_o && !busy_o, "engine did not return idle after consume");
    end
  endtask

  initial begin
    clear_inputs();
    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    // 4x8 unsigned dot: (1*5)+(2*6)+(3*7)+(4*8)=70.
    launch_and_check(2'b00, 32'h04030201, 32'h08070605,
                     64'd0, 1'b0, 1'b0, 1'b0, 64'd70, 5);

    // 2x16 unsigned dot + accumulator: 2*4 + 3*5 + 9 = 32.
    launch_and_check(2'b01, {16'd3,16'd2}, {16'd5,16'd4},
                     64'd9, 1'b0, 1'b0, 1'b1, 64'd32, 9);

    // Signed scalar: -7 * 6 = -42.
    launch_and_check(2'b10, 32'hfffffff9, 32'd6,
                     64'd0, 1'b1, 1'b1, 1'b0, -64'sd42, 17);

    // Kill must discard an in-flight operation immediately.
    @(negedge clk);
    simd_mode_i = 2'b10;
    operand_a_i = 32'd123;
    operand_b_i = 32'd456;
    valid_i = 1'b1;
    @(posedge clk); #1;
    valid_i = 1'b0;
    check(busy_o, "kill test did not launch");
    kill_i = 1'b1;
    @(posedge clk); #1;
    kill_i = 1'b0;
    check(ready_o && !result_valid_o, "kill did not cancel operation");

    $display("cv32e40p_sparv_mac_dotp_engine_tb: PASS");
    $finish;
  end
endmodule
