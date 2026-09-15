// Directed smoke test for cv32e40p_hamsa_frontend.

module cv32e40p_hamsa_frontend_tb;
  logic clk;
  logic rst_n;
  logic invalidate;
  logic redirect;
  logic [31:0] redirect_pc;
  logic lookup_valid;
  logic [31:0] lookup_pc;
  logic lookup_ready;
  logic lookup_hit;
  logic refill_valid;
  logic [31:0] refill_addr;
  logic [127:0] refill_data;
  logic pair_valid;
  logic pair_ready;
  logic [31:0] inst1;
  logic [31:0] pc1;
  logic inst1_c;
  logic inst1_illegal;
  logic inst2_valid;
  logic [31:0] inst2;
  logic [31:0] pc2;
  logic inst2_c;
  logic inst2_illegal;
  logic [31:0] next_pc;

  localparam logic [31:0] ADDI_X1_X0_1 = 32'h00100093;
  localparam logic [31:0] ADDI_X2_X0_2 = 32'h00200113;
  localparam logic [31:0] ADD_X3_X1_X2 = 32'h002081b3;
  localparam logic [31:0] NOP = 32'h00000013;

  cv32e40p_hamsa_frontend dut (
      .clk(clk),
      .rst_n(rst_n),
      .invalidate_i(invalidate),
      .redirect_i(redirect),
      .redirect_pc_i(redirect_pc),
      .lookup_valid_i(lookup_valid),
      .lookup_pc_i(lookup_pc),
      .lookup_ready_o(lookup_ready),
      .lookup_hit_o(lookup_hit),
      .refill_valid_i(refill_valid),
      .refill_addr_i(refill_addr),
      .refill_data_i(refill_data),
      .pair_valid_o(pair_valid),
      .pair_ready_i(pair_ready),
      .inst1_o(inst1),
      .pc1_o(pc1),
      .inst1_compressed_o(inst1_c),
      .inst1_illegal_c_o(inst1_illegal),
      .inst2_valid_o(inst2_valid),
      .inst2_o(inst2),
      .pc2_o(pc2),
      .inst2_compressed_o(inst2_c),
      .inst2_illegal_c_o(inst2_illegal),
      .next_pc_o(next_pc)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    invalidate = 1'b0;
    redirect = 1'b0;
    redirect_pc = '0;
    lookup_valid = 1'b0;
    lookup_pc = '0;
    refill_valid = 1'b0;
    refill_addr = '0;
    refill_data = '0;
    pair_ready = 1'b1;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // Refill one 128-bit line at 0x1000.
    @(negedge clk);
    refill_addr  = 32'h00001000;
    refill_data  = {NOP, ADD_X3_X1_X2, ADDI_X2_X0_2, ADDI_X1_X0_1};
    refill_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    refill_valid = 1'b0;

    lookup_pc    = 32'h00001000;
    lookup_valid = 1'b1;
    #1;
    if (!lookup_hit) $fatal(1, "expected L0 hit");
    @(posedge clk);
    @(negedge clk);
    lookup_valid = 1'b0;

    #1;
    if (!pair_valid) $fatal(1, "expected pair_valid");
    if (inst1 !== ADDI_X1_X0_1) $fatal(1, "bad inst1 %h", inst1);
    if (!inst2_valid || inst2 !== ADDI_X2_X0_2) $fatal(1, "bad inst2 %h", inst2);
    if (pc1 !== 32'h00001000 || pc2 !== 32'h00001004)
      $fatal(1, "bad PCs pc1=%h pc2=%h", pc1, pc2);
    if (next_pc !== 32'h00001008) $fatal(1, "bad next_pc %h", next_pc);
    if (inst1_c || inst2_c || inst1_illegal || inst2_illegal)
      $fatal(1, "unexpected compressed/illegal metadata");

    // Redirect must drop any buffered pair and publish the redirect PC.
    pair_ready  = 1'b0;
    redirect_pc = 32'h00002000;
    redirect    = 1'b1;
    @(posedge clk);
    @(negedge clk);
    redirect = 1'b0;
    #1;
    if (pair_valid) $fatal(1, "redirect failed to clear pair");
    if (next_pc !== 32'h00002000) $fatal(1, "redirect next_pc mismatch");

    $display("cv32e40p_hamsa_frontend_tb: PASS");
    $finish;
  end
endmodule
