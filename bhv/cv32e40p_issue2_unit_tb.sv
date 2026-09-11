// Directed unit test for the restricted secondary issue lane.

module cv32e40p_issue2_unit_tb;
  import cv32e40p_pkg::*;

  logic clk;
  logic rst_n;
  logic issue_valid;
  logic [31:0] instr;
  logic [31:0] rs1_data;
  logic [31:0] rs2_data;
  logic kill;
  logic wb_ready;
  logic issue_ready;
  logic decode_illegal;
  logic wb_valid;
  logic [4:0] wb_rd;
  logic [31:0] wb_data;

  cv32e40p_issue2_lane dut (
      .clk             (clk),
      .rst_n           (rst_n),
      .issue_valid_i   (issue_valid),
      .instr_i         (instr),
      .rs1_data_i      (rs1_data),
      .rs2_data_i      (rs2_data),
      .kill_i          (kill),
      .wb_ready_i      (wb_ready),
      .issue_ready_o   (issue_ready),
      .decode_illegal_o(decode_illegal),
      .wb_valid_o      (wb_valid),
      .wb_rd_o         (wb_rd),
      .wb_data_o       (wb_data)
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

  task automatic issue_and_check(
      input logic [31:0] test_instr,
      input logic [31:0] a,
      input logic [31:0] b,
      input logic [4:0] expected_rd,
      input logic [31:0] expected_data
  );
    begin
      while (!issue_ready) @(posedge clk);
      instr       <= test_instr;
      rs1_data    <= a;
      rs2_data    <= b;
      issue_valid <= 1'b1;
      @(posedge clk);
      issue_valid <= 1'b0;
      instr       <= '0;

      do @(posedge clk); while (!wb_valid);
      if (wb_rd !== expected_rd || wb_data !== expected_data) begin
        $error("Issue2 mismatch: rd=%0d data=%h expected rd=%0d data=%h",
               wb_rd, wb_data, expected_rd, expected_data);
        $fatal(1);
      end
      @(posedge clk);
    end
  endtask

  initial begin
    clk         = 1'b0;
    rst_n       = 1'b0;
    issue_valid = 1'b0;
    instr       = '0;
    rs1_data    = '0;
    rs2_data    = '0;
    kill        = 1'b0;
    wb_ready    = 1'b1;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // add x5, x1, x2 => 12 + 7 = 19
    issue_and_check(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd5),
                    32'd12, 32'd7, 5'd5, 32'd19);

    // sub x6, x1, x2 => 12 - 7 = 5
    issue_and_check(enc_r(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd6),
                    32'd12, 32'd7, 5'd6, 32'd5);

    // and x7, x1, x2
    issue_and_check(enc_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd7),
                    32'hF0F0_AA55, 32'h0FF0_0F0F, 5'd7, 32'h00F0_0A05);

    // addi x8, x1, -3 => 12 - 3 = 9
    issue_and_check(enc_i(12'hFFD, 5'd1, 3'b000, 5'd8),
                    32'd12, 32'd0, 5'd8, 32'd9);

    // slli x9, x1, 4
    issue_and_check(enc_i({7'b0000000, 5'd4}, 5'd1, 3'b001, 5'd9),
                    32'h0000_0011, 32'd0, 5'd9, 32'h0000_0110);

    // MUL encoding is intentionally illegal on Issue2.
    while (!issue_ready) @(posedge clk);
    instr       <= enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd10);
    rs1_data    <= 32'd3;
    rs2_data    <= 32'd4;
    issue_valid <= 1'b1;
    #1;
    if (!decode_illegal) begin
      $error("MUL must be rejected by Issue2 decoder");
      $fatal(1);
    end
    @(posedge clk);
    issue_valid <= 1'b0;

    // Kill must remove a queued Issue2 writeback.
    wb_ready = 1'b0;
    while (!issue_ready) @(posedge clk);
    instr       <= enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd11);
    rs1_data    <= 32'd1;
    rs2_data    <= 32'd2;
    issue_valid <= 1'b1;
    @(posedge clk);
    issue_valid <= 1'b0;
    kill        <= 1'b1;
    @(posedge clk);
    kill        <= 1'b0;
    wb_ready    <= 1'b1;
    @(posedge clk);
    if (wb_valid) begin
      $error("Killed Issue2 operation remained valid");
      $fatal(1);
    end

    $display("cv32e40p_issue2_unit_tb: PASS");
    $finish;
  end

endmodule
