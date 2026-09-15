`timescale 1ns/1ps

module cv32e40p_sparv_prefetch_ctrl_tb;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic redirect_i;
  logic [31:0] redirect_pc_i;
  logic demand_lookup_i;
  logic [31:0] demand_pc_i;
  logic demand_hit_i;
  logic demand_miss_i;
  logic demand_refill_i;
  logic [31:0] demand_refill_addr_i;
  logic refill_busy_i;
  logic prefetch_accept_i;
  logic prefetch_valid_o;
  logic [31:0] prefetch_addr_o;
  logic prefetch_candidate_o;
  logic prefetch_suppressed_o;

  always #5 clk = ~clk;

  cv32e40p_sparv_prefetch_ctrl dut (
      .clk,
      .rst_n,
      .redirect_i,
      .redirect_pc_i,
      .demand_lookup_i,
      .demand_pc_i,
      .demand_hit_i,
      .demand_miss_i,
      .demand_refill_i,
      .demand_refill_addr_i,
      .refill_busy_i,
      .prefetch_accept_i,
      .prefetch_valid_o,
      .prefetch_addr_o,
      .prefetch_candidate_o,
      .prefetch_suppressed_o
  );

  task automatic clear_inputs;
    begin
      redirect_i           = 1'b0;
      redirect_pc_i        = 32'd0;
      demand_lookup_i      = 1'b0;
      demand_pc_i          = 32'd0;
      demand_hit_i         = 1'b0;
      demand_miss_i        = 1'b0;
      demand_refill_i      = 1'b0;
      demand_refill_addr_i = 32'd0;
      refill_busy_i        = 1'b0;
      prefetch_accept_i    = 1'b0;
    end
  endtask

  task automatic check(input logic cond, input string msg);
    begin
      if (!cond) begin
        $display("FAIL: %s", msg);
        $fatal(1);
      end
    end
  endtask

  initial begin
    clear_inputs();
    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    // A hit in line 0x100 trains prefetch line 0x110.
    @(negedge clk);
    demand_lookup_i = 1'b1;
    demand_hit_i    = 1'b1;
    demand_pc_i     = 32'h0000_0108;
    @(posedge clk);
    #1;
    clear_inputs();
    #1;
    check(prefetch_valid_o, "candidate should issue after demand hit");
    check(prefetch_addr_o == 32'h0000_0110, "next-line address mismatch");

    // A demand miss suppresses speculative traffic without destroying it.
    demand_miss_i = 1'b1;
    #1;
    check(!prefetch_valid_o, "demand miss must win arbitration");
    check(prefetch_suppressed_o, "suppression instrumentation missing");
    demand_miss_i = 1'b0;
    #1;
    check(prefetch_valid_o, "candidate should survive temporary demand miss");

    // Accepting the request consumes the candidate.
    prefetch_accept_i = 1'b1;
    @(posedge clk);
    #1;
    clear_inputs();
    #1;
    check(!prefetch_candidate_o, "accepted prefetch should clear candidate");

    // A refill commit also trains the next sequential line.
    demand_refill_i      = 1'b1;
    demand_refill_addr_i = 32'h0000_0230;
    @(posedge clk);
    #1;
    clear_inputs();
    #1;
    check(prefetch_valid_o, "refill should create candidate");
    check(prefetch_addr_o == 32'h0000_0240, "refill-trained address mismatch");

    // Redirect retargets speculation to the redirected stream.
    redirect_i    = 1'b1;
    redirect_pc_i = 32'h0000_0806;
    #1;
    check(!prefetch_valid_o, "redirect cycle must suppress prefetch");
    @(posedge clk);
    #1;
    clear_inputs();
    #1;
    check(prefetch_valid_o, "redirect should train new sequential candidate");
    check(prefetch_addr_o == 32'h0000_0810, "redirect-trained address mismatch");

    // Refill busy suppresses speculation until the path becomes idle.
    refill_busy_i = 1'b1;
    #1;
    check(!prefetch_valid_o, "busy refill engine must suppress prefetch");
    refill_busy_i = 1'b0;
    #1;
    check(prefetch_valid_o, "prefetch should resume after refill becomes idle");

    $display("cv32e40p_sparv_prefetch_ctrl_tb: PASS");
    $finish;
  end

endmodule
