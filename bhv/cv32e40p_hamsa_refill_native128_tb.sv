`timescale 1ns/1ps

module cv32e40p_hamsa_refill_native128_tb;
  logic clk = 0;
  logic rst_n = 0;
  logic flush;
  logic miss_valid;
  logic [31:0] miss_pc;
  logic miss_ready;
  logic line_req;
  logic [31:0] line_addr;
  logic line_gnt;
  logic line_rvalid;
  logic [127:0] line_rdata;
  logic refill_valid;
  logic [31:0] refill_addr;
  logic [127:0] refill_data;
  logic busy;

  always #5 clk = ~clk;

  cv32e40p_hamsa_refill_native128 dut (
      .clk(clk), .rst_n(rst_n), .flush_i(flush),
      .miss_valid_i(miss_valid), .miss_pc_i(miss_pc), .miss_ready_o(miss_ready),
      .line_req_o(line_req), .line_addr_o(line_addr),
      .line_gnt_i(line_gnt), .line_rvalid_i(line_rvalid), .line_rdata_i(line_rdata),
      .refill_valid_o(refill_valid), .refill_addr_o(refill_addr),
      .refill_data_o(refill_data), .busy_o(busy)
  );

  task automatic expect(input logic cond, input string msg);
    if (!cond) begin
      $display("FAIL: %s", msg);
      $fatal(1);
    end
  endtask

  initial begin
    flush = 0;
    miss_valid = 0;
    miss_pc = 0;
    line_gnt = 0;
    line_rvalid = 0;
    line_rdata = '0;

    repeat (3) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    expect(miss_ready, "engine should start ready");
    miss_pc = 32'h0000_1236;
    miss_valid = 1;
    @(posedge clk);
    miss_valid = 0;
    #1;
    expect(line_req, "native line request missing");
    expect(line_addr == 32'h0000_1230, "line address must align to 16 bytes");
    expect(busy, "busy should assert during request");

    line_gnt = 1;
    @(posedge clk);
    line_gnt = 0;
    #1;
    expect(!line_req, "request must drop after grant");

    line_rdata = 128'hD3D2D1D0_C3C2C1C0_B3B2B1B0_A3A2A1A0;
    line_rvalid = 1;
    @(posedge clk);
    line_rvalid = 0;
    #1;
    expect(refill_valid, "refill pulse missing");
    expect(refill_addr == 32'h0000_1230, "refill address mismatch");
    expect(refill_data == line_rdata, "refill data mismatch");
    expect(!busy, "engine should return idle after response");

    @(posedge clk);
    #1;
    expect(!refill_valid, "refill pulse must be one cycle");

    // Flush must cancel an outstanding request.
    miss_pc = 32'h0000_4004;
    miss_valid = 1;
    @(posedge clk);
    miss_valid = 0;
    #1;
    expect(line_req, "second request missing");
    flush = 1;
    @(posedge clk);
    flush = 0;
    #1;
    expect(!busy && miss_ready, "flush must cancel outstanding refill");

    $display("PASS: native 128-bit refill engine");
    $finish;
  end
endmodule
