// Directed integration test for IDU + 5R3W register file + Issue2 lane.

module cv32e40p_dual_issue_pair_unit_tb;
  import cv32e40p_pkg::*;

  logic clk;
  logic rst_n;

  logic inst1_valid;
  logic [31:0] inst1;
  logic inst2_valid;
  logic [31:0] inst2;

  logic [5:0] raddr_a, raddr_b, raddr_c;
  logic [31:0] rdata_a, rdata_b, rdata_c;

  logic [5:0] waddr_a, waddr_b;
  logic [31:0] wdata_a, wdata_b;
  logic we_a, we_b;

  logic issue2_kill;
  logic issue1_valid_o;
  logic issue2_valid_o;
  logic issue2_fire_o;
  logic raw_hazard;
  logic waw_hazard;
  logic issue2_unsupported;
  logic issue1_serializing;
  logic issue2_decode_illegal;
  logic issue2_wb_valid;
  logic [4:0] issue2_wb_rd;
  logic [31:0] issue2_wb_data;

  cv32e40p_dual_issue_pair_unit dut (
      .clk(clk), .rst_n(rst_n),
      .inst1_valid_i(inst1_valid), .inst1_i(inst1),
      .inst2_valid_i(inst2_valid), .inst2_i(inst2),
      .issue1_raddr_a_i(raddr_a), .issue1_raddr_b_i(raddr_b),
      .issue1_raddr_c_i(raddr_c), .issue1_rdata_a_o(rdata_a),
      .issue1_rdata_b_o(rdata_b), .issue1_rdata_c_o(rdata_c),
      .issue1_waddr_a_i(waddr_a), .issue1_wdata_a_i(wdata_a), .issue1_we_a_i(we_a),
      .issue1_waddr_b_i(waddr_b), .issue1_wdata_b_i(wdata_b), .issue1_we_b_i(we_b),
      .issue2_kill_i(issue2_kill),
      .issue1_valid_o(issue1_valid_o), .issue2_valid_o(issue2_valid_o),
      .issue2_fire_o(issue2_fire_o), .raw_hazard_o(raw_hazard),
      .waw_hazard_o(waw_hazard), .issue2_unsupported_o(issue2_unsupported),
      .issue1_serializing_o(issue1_serializing),
      .issue2_decode_illegal_o(issue2_decode_illegal),
      .issue2_wb_valid_o(issue2_wb_valid), .issue2_wb_rd_o(issue2_wb_rd),
      .issue2_wb_data_o(issue2_wb_data)
  );

  always #5 clk = ~clk;

  function automatic logic [31:0] enc_r(
      input logic [6:0] funct7,
      input logic [4:0] rs2,
      input logic [4:0] rs1,
      input logic [2:0] funct3,
      input logic [4:0] rd
  );
    return {funct7, rs2, rs1, funct3, rd, OPCODE_OP};
  endfunction

  function automatic logic [31:0] enc_i(
      input logic [11:0] imm,
      input logic [4:0] rs1,
      input logic [2:0] funct3,
      input logic [4:0] rd
  );
    return {imm, rs1, funct3, rd, OPCODE_OPIMM};
  endfunction

  task automatic rf_write_a(input logic [4:0] rd, input logic [31:0] data);
    begin
      waddr_a = {1'b0, rd};
      wdata_a = data;
      we_a    = 1'b1;
      @(posedge clk);
      #1;
      we_a    = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    inst1_valid = 1'b0;
    inst2_valid = 1'b0;
    inst1 = '0;
    inst2 = '0;
    raddr_a = '0;
    raddr_b = '0;
    raddr_c = '0;
    waddr_a = '0;
    waddr_b = '0;
    wdata_a = '0;
    wdata_b = '0;
    we_a = 1'b0;
    we_b = 1'b0;
    issue2_kill = 1'b0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // Seed x1=12 and x2=7 through the baseline Issue1 WB port.
    rf_write_a(5'd1, 32'd12);
    rf_write_a(5'd2, 32'd7);

    // NOP on Issue1 + ADD x5,x1,x2 on Issue2.
    inst1 = enc_i(12'd0, 5'd0, 3'b000, 5'd0);
    inst2 = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd5);
    inst1_valid = 1'b1;
    inst2_valid = 1'b1;
    #1;
    if (!issue2_fire_o || raw_hazard || waw_hazard || issue2_unsupported) begin
      $error("Independent ALU pair did not issue");
      $fatal(1);
    end
    @(posedge clk);
    inst1_valid = 1'b0;
    inst2_valid = 1'b0;

    // Wait for Issue2 result and its RF write.
    wait (issue2_wb_valid);
    if (issue2_wb_rd !== 5'd5 || issue2_wb_data !== 32'd19) begin
      $error("Issue2 result mismatch rd=%0d data=%0d", issue2_wb_rd, issue2_wb_data);
      $fatal(1);
    end
    @(posedge clk);
    #1;
    raddr_a = {1'b0, 5'd5};
    #1;
    if (rdata_a !== 32'd19) begin
      $error("Issue2 writeback did not reach 5R3W RF: %0d", rdata_a);
      $fatal(1);
    end

    // RAW: ADDI x6,x0,1 paired with ADD x7,x6,x2 must be blocked.
    inst1 = enc_i(12'd1, 5'd0, 3'b000, 5'd6);
    inst2 = enc_r(7'b0000000, 5'd2, 5'd6, 3'b000, 5'd7);
    inst1_valid = 1'b1;
    inst2_valid = 1'b1;
    #1;
    if (!raw_hazard || issue2_fire_o) begin
      $error("RAW dependent pair was not blocked");
      $fatal(1);
    end

    // WAW: both instructions target x8.
    inst1 = enc_i(12'd3, 5'd0, 3'b000, 5'd8);
    inst2 = enc_i(12'd4, 5'd0, 3'b000, 5'd8);
    #1;
    if (!waw_hazard || issue2_fire_o) begin
      $error("WAW pair was not blocked");
      $fatal(1);
    end

    inst1_valid = 1'b0;
    inst2_valid = 1'b0;
    $display("cv32e40p_dual_issue_pair_unit_tb: PASS");
    $finish;
  end

endmodule
