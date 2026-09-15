`timescale 1ns/1ps

module cv32e40p_hamsa_refill_32to128_tb;
  logic clk = 0;
  logic rst_n = 0;
  logic flush_i = 0;
  logic miss_valid_i = 0;
  logic [31:0] miss_pc_i = 0;
  logic miss_ready_o;
  logic instr_req_o;
  logic [31:0] instr_addr_o;
  logic instr_gnt_i = 0;
  logic instr_rvalid_i = 0;
  logic [31:0] instr_rdata_i = 0;
  logic refill_valid_o;
  logic [31:0] refill_addr_o;
  logic [127:0] refill_data_o;
  logic busy_o;

  always #5 clk = ~clk;

  cv32e40p_hamsa_refill_32to128 dut (
      .clk(clk), .rst_n(rst_n), .flush_i(flush_i),
      .miss_valid_i(miss_valid_i), .miss_pc_i(miss_pc_i), .miss_ready_o(miss_ready_o),
      .instr_req_o(instr_req_o), .instr_addr_o(instr_addr_o),
      .instr_gnt_i(instr_gnt_i), .instr_rvalid_i(instr_rvalid_i), .instr_rdata_i(instr_rdata_i),
      .refill_valid_o(refill_valid_o), .refill_addr_o(refill_addr_o),
      .refill_data_o(refill_data_o), .busy_o(busy_o)
  );

  task automatic service_beat(input logic [31:0] expected_addr,
                              input logic [31:0] data);
    begin
      wait (instr_req_o);
      if (instr_addr_o !== expected_addr)
        $fatal(1, "address mismatch: got %08x expected %08x", instr_addr_o, expected_addr);
      @(negedge clk); instr_gnt_i = 1'b1;
      @(negedge clk); instr_gnt_i = 1'b0;
      @(negedge clk); instr_rdata_i = data; instr_rvalid_i = 1'b1;
      @(negedge clk); instr_rvalid_i = 1'b0;
    end
  endtask

  initial begin
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    @(negedge clk);
    miss_pc_i = 32'h0000_1236;
    miss_valid_i = 1'b1;
    @(negedge clk);
    miss_valid_i = 1'b0;

    service_beat(32'h0000_1230, 32'h1111_0000);
    service_beat(32'h0000_1234, 32'h2222_0001);
    service_beat(32'h0000_1238, 32'h3333_0002);
    service_beat(32'h0000_123c, 32'h4444_0003);

    wait (refill_valid_o);
    if (refill_addr_o !== 32'h0000_1230)
      $fatal(1, "refill address mismatch");
    if (refill_data_o !== 128'h44440003_33330002_22220001_11110000)
      $fatal(1, "refill data mismatch: %032x", refill_data_o);

    $display("HAMSA refill adapter test PASS");
    $finish;
  end
endmodule
