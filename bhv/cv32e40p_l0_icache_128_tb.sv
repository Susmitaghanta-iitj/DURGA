module cv32e40p_l0_icache_128_tb;
  logic clk, rst_n, invalidate, lookup_valid, refill_valid;
  logic [31:0] lookup_pc, refill_addr;
  logic [127:0] refill_data;
  logic hit, same_line;
  logic [31:0] inst1, inst2;

  cv32e40p_l0_icache_128 dut (
    .clk(clk), .rst_n(rst_n), .invalidate_i(invalidate),
    .lookup_valid_i(lookup_valid), .lookup_pc_i(lookup_pc),
    .lookup_hit_o(hit), .inst1_o(inst1), .inst2_o(inst2),
    .inst2_same_line_o(same_line),
    .refill_valid_i(refill_valid), .refill_addr_i(refill_addr),
    .refill_data_i(refill_data)
  );

  always #5 clk=~clk;
  initial begin
    clk=0; rst_n=0; invalidate=0; lookup_valid=0; refill_valid=0;
    lookup_pc=0; refill_addr=0; refill_data=0;
    repeat(2) @(posedge clk); rst_n=1;

    refill_addr=32'h0000_0100;
    refill_data={32'h44444444,32'h33333333,32'h22222222,32'h11111111};
    refill_valid=1; @(posedge clk); refill_valid=0;

    lookup_valid=1; lookup_pc=32'h0000_0100; #1;
    if(!hit || inst1!==32'h11111111 || inst2!==32'h22222222 || !same_line)
      $fatal(1,"word0 lookup failed");

    lookup_pc=32'h0000_0108; #1;
    if(!hit || inst1!==32'h33333333 || inst2!==32'h44444444 || !same_line)
      $fatal(1,"word2 lookup failed");

    lookup_pc=32'h0000_010C; #1;
    if(!hit || inst1!==32'h44444444 || same_line)
      $fatal(1,"end-of-line handling failed");

    invalidate=1; @(posedge clk); invalidate=0; #1;
    if(hit) $fatal(1,"invalidate failed");

    $display("cv32e40p_l0_icache_128_tb: PASS");
    $finish;
  end
endmodule
