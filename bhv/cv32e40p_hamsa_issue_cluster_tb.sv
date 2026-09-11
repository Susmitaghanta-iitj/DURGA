// Directed smoke test for cv32e40p_hamsa_issue_cluster.

module cv32e40p_hamsa_issue_cluster_tb;
  logic clk;
  logic rst_n;
  logic flush;
  logic pair_fire;
  logic primary_commit_safe;
  logic inst1_valid;
  logic [31:0] inst1;
  logic inst2_valid;
  logic [31:0] inst2;
  logic primary_wb_we;
  logic [5:0] primary_wb_addr;
  logic [31:0] primary_wb_data;
  logic primary_alu_we;
  logic [5:0] primary_alu_addr;
  logic [31:0] primary_alu_data;
  logic primary_ex_we;
  logic [5:0] primary_ex_addr;
  logic [31:0] primary_ex_data;
  logic arb_alu_we;
  logic [5:0] arb_alu_addr;
  logic [31:0] arb_alu_data;
  logic inst2_consumed;
  logic issue2_pending;
  logic issue2_blocked;

  function automatic logic [31:0] enc_add(
      input logic [4:0] rd,
      input logic [4:0] rs1,
      input logic [4:0] rs2
  );
    return {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
  endfunction

  function automatic logic [31:0] enc_addi(
      input logic [4:0] rd,
      input logic [4:0] rs1,
      input logic [11:0] imm
  );
    return {imm, rs1, 3'b000, rd, 7'b0010011};
  endfunction

  cv32e40p_hamsa_issue_cluster dut (
      .clk(clk),
      .rst_n(rst_n),
      .flush_i(flush),
      .pair_fire_i(pair_fire),
      .primary_commit_safe_i(primary_commit_safe),
      .inst1_valid_i(inst1_valid),
      .inst1_i(inst1),
      .inst2_valid_i(inst2_valid),
      .inst2_i(inst2),
      .primary_wb_we_i(primary_wb_we),
      .primary_wb_addr_i(primary_wb_addr),
      .primary_wb_data_i(primary_wb_data),
      .primary_alu_we_i(primary_alu_we),
      .primary_alu_addr_i(primary_alu_addr),
      .primary_alu_data_i(primary_alu_data),
      .primary_ex_we_i(primary_ex_we),
      .primary_ex_addr_i(primary_ex_addr),
      .primary_ex_data_i(primary_ex_data),
      .arb_alu_we_o(arb_alu_we),
      .arb_alu_addr_o(arb_alu_addr),
      .arb_alu_data_o(arb_alu_data),
      .inst2_consumed_o(inst2_consumed),
      .issue2_pending_o(issue2_pending),
      .issue2_blocked_o(issue2_blocked)
  );

  always #5 clk = ~clk;

  task automatic seed_reg(input logic [4:0] rd, input logic [31:0] data);
    begin
      @(negedge clk);
      primary_wb_we   = 1'b1;
      primary_wb_addr = {1'b0, rd};
      primary_wb_data = data;
      @(posedge clk);
      @(negedge clk);
      primary_wb_we   = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    flush = 1'b0;
    pair_fire = 1'b0;
    primary_commit_safe = 1'b0;
    inst1_valid = 1'b0;
    inst1 = '0;
    inst2_valid = 1'b0;
    inst2 = '0;
    primary_wb_we = 1'b0;
    primary_wb_addr = '0;
    primary_wb_data = '0;
    primary_alu_we = 1'b0;
    primary_alu_addr = '0;
    primary_alu_data = '0;
    primary_ex_we = 1'b0;
    primary_ex_addr = '0;
    primary_ex_data = '0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    seed_reg(5'd1, 32'd10);
    seed_reg(5'd2, 32'd7);

    // Independent pair: Issue1 writes x5, Issue2 computes x6=x1+x2.
    // Keep primary_commit_safe low to prove the younger result cannot retire
    // before the older instruction is architecturally safe.
    @(negedge clk);
    inst1       = enc_addi(5'd5, 5'd0, 12'd1);
    inst2       = enc_add(5'd6, 5'd1, 5'd2);
    inst1_valid = 1'b1;
    inst2_valid = 1'b1;
    pair_fire   = 1'b1;
    #1;
    if (!inst2_consumed) $fatal(1, "Issue2 should have been consumed");
    @(posedge clk);
    @(negedge clk);
    pair_fire   = 1'b0;
    inst1_valid = 1'b0;
    inst2_valid = 1'b0;

    #1;
    if (!issue2_pending) $fatal(1, "Issue2 result should be buffered");
    if (arb_alu_we) $fatal(1, "Issue2 retired before primary commit-safe");

    primary_commit_safe = 1'b1;
    #1;
    if (!arb_alu_we || arb_alu_addr !== 6'd6 || arb_alu_data !== 32'd17)
      $fatal(1, "bad gated Issue2 WB addr=%0d data=%h", arb_alu_addr, arb_alu_data);
    @(posedge clk);
    @(negedge clk);
    primary_commit_safe = 1'b0;

    // RAW pair must be blocked: inst1 rd=x3, inst2 rs1=x3.
    inst1       = enc_addi(5'd3, 5'd0, 12'd9);
    inst2       = enc_add(5'd7, 5'd3, 5'd2);
    inst1_valid = 1'b1;
    inst2_valid = 1'b1;
    pair_fire   = 1'b1;
    #1;
    if (inst2_consumed || !issue2_blocked)
      $fatal(1, "RAW pair was not blocked");

    $display("cv32e40p_hamsa_issue_cluster_tb: PASS");
    $finish;
  end
endmodule
