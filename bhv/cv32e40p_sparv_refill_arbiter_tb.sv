`timescale 1ns/1ps
module cv32e40p_sparv_refill_arbiter_tb;
  logic clk=0, rst_n=0, flush_i=0;
  logic demand_valid_i=0; logic [31:0] demand_addr_i=0;
  logic prefetch_valid_i=0; logic [31:0] prefetch_addr_i=0; logic prefetch_cached_i=0;
  logic refill_req_valid_o; logic [31:0] refill_req_addr_o;
  logic refill_req_ready_i=0, refill_complete_i=0;
  logic demand_accept_o, prefetch_accept_o, refill_is_prefetch_o;
  always #5 clk=~clk;
  cv32e40p_sparv_refill_arbiter dut(.*);
  task tick; begin @(posedge clk); #1; end endtask
  task check(input logic c,input string m); begin if(!c) begin $display("FAIL: %s",m); $fatal(1); end end endtask
  initial begin
    repeat(2) tick(); rst_n=1; tick();
    refill_req_ready_i=1;
    demand_valid_i=1; demand_addr_i=32'h100;
    prefetch_valid_i=1; prefetch_addr_i=32'h200; #1;
    check(refill_req_valid_o && refill_req_addr_o==32'h100,"demand must win");
    check(demand_accept_o && !prefetch_accept_o,"demand handshake");
    tick(); demand_valid_i=0;
    refill_complete_i=1; #1; check(!refill_is_prefetch_o,"demand completion classification");
    tick(); refill_complete_i=0;

    prefetch_valid_i=1; prefetch_cached_i=0; #1;
    check(refill_req_valid_o && refill_req_addr_o==32'h200,"prefetch may use idle refill path");
    check(prefetch_accept_o,"prefetch handshake"); tick();
    prefetch_valid_i=0; refill_complete_i=1; #1;
    check(refill_is_prefetch_o,"prefetch completion classification"); tick(); refill_complete_i=0;

    prefetch_valid_i=1; prefetch_cached_i=1; #1;
    check(!refill_req_valid_o,"cached prefetch must be suppressed");
    prefetch_cached_i=0; flush_i=1; tick(); flush_i=0; prefetch_valid_i=0;
    refill_complete_i=1; #1; check(!refill_is_prefetch_o,"flush must clear source tracking");
    $display("PASS: SPARV refill arbiter"); $finish;
  end
endmodule
