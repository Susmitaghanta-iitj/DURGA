`timescale 1ns/1ps
module cv32e40p_sparv_prefetch_directory_tb;
  logic clk=0, rst_n=0, invalidate_i=0;
  logic refill_valid_i=0, refill_is_prefetch_i=0;
  logic [31:0] refill_addr_i=0;
  logic demand_lookup_i=0, demand_hit_i=0;
  logic [31:0] demand_pc_i=0, probe_addr_i=0;
  logic probe_hit_o, useful_prefetch_o, wasted_prefetch_o;

  always #5 clk = ~clk;

  cv32e40p_sparv_prefetch_directory #(.LINES(8)) dut (.*);

  task tick; begin @(posedge clk); #1; end endtask
  task check(input logic cond, input string msg); begin
    if (!cond) begin $display("FAIL: %s", msg); $fatal(1); end
  end endtask

  initial begin
    repeat (2) tick(); rst_n=1; tick();

    // Fill line 0x100 as speculative and verify arbitrary probe hit.
    refill_valid_i=1; refill_is_prefetch_i=1; refill_addr_i=32'h100; tick();
    refill_valid_i=0; refill_is_prefetch_i=0; probe_addr_i=32'h108; #1;
    check(probe_hit_o, "prefetched line must probe hit");

    // First architectural demand of the line marks the prefetch useful.
    demand_lookup_i=1; demand_hit_i=1; demand_pc_i=32'h104; #1;
    check(useful_prefetch_o, "first demand hit must mark prefetch useful");
    tick(); demand_lookup_i=0; demand_hit_i=0; #1;
    check(!useful_prefetch_o, "useful event must pulse once");

    // Refill another speculative line into index 0, then replace it before use.
    refill_valid_i=1; refill_is_prefetch_i=1; refill_addr_i=32'h180; tick();
    refill_addr_i=32'h200; refill_is_prefetch_i=0; #1;
    check(wasted_prefetch_o, "replacement of unused prefetched line must be waste");
    tick(); refill_valid_i=0;

    // Invalidation clears state without creating a replacement-waste event.
    invalidate_i=1; tick(); invalidate_i=0;
    probe_addr_i=32'h200; #1;
    check(!probe_hit_o, "invalidate must clear directory");

    $display("PASS: SPARV prefetch directory");
    $finish;
  end
endmodule
