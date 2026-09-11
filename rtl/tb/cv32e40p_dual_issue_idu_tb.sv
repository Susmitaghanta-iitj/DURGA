`timescale 1ns/1ps

module cv32e40p_dual_issue_idu_tb;

  logic        inst1_valid;
  logic [31:0] inst1;
  logic        inst2_valid;
  logic [31:0] inst2;
  logic        issue1_valid;
  logic        issue2_valid;
  logic        raw_hazard;
  logic        waw_hazard;
  logic        issue2_unsupported;
  logic        issue1_serializing;
  logic [4:0]  inst1_rd;
  logic [4:0]  inst2_rs1;
  logic [4:0]  inst2_rs2;
  logic [4:0]  inst2_rd;

  cv32e40p_dual_issue_idu dut (
      .inst1_valid_i(inst1_valid),
      .inst1_i(inst1),
      .inst2_valid_i(inst2_valid),
      .inst2_i(inst2),
      .issue1_valid_o(issue1_valid),
      .issue2_valid_o(issue2_valid),
      .raw_hazard_o(raw_hazard),
      .waw_hazard_o(waw_hazard),
      .issue2_unsupported_o(issue2_unsupported),
      .issue1_serializing_o(issue1_serializing),
      .inst1_rd_o(inst1_rd),
      .inst2_rs1_o(inst2_rs1),
      .inst2_rs2_o(inst2_rs2),
      .inst2_rd_o(inst2_rd)
  );

  function automatic logic [31:0] enc_r(
      input logic [6:0] funct7,
      input logic [4:0] rs2,
      input logic [4:0] rs1,
      input logic [2:0] funct3,
      input logic [4:0] rd,
      input logic [6:0] opcode
  );
    return {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_i(
      input logic [11:0] imm,
      input logic [4:0] rs1,
      input logic [2:0] funct3,
      input logic [4:0] rd,
      input logic [6:0] opcode
  );
    return {imm, rs1, funct3, rd, opcode};
  endfunction

  task automatic expect_issue2(input logic expected, input string name);
    #1;
    if (issue2_valid !== expected) begin
      $error("%s: issue2_valid=%0b expected=%0b raw=%0b waw=%0b unsupported=%0b serial=%0b",
             name, issue2_valid, expected, raw_hazard, waw_hazard,
             issue2_unsupported, issue1_serializing);
      $fatal(1);
    end
  endtask

  initial begin
    inst1_valid = 1'b1;
    inst2_valid = 1'b1;

    // add x3,x1,x2 ; xor x6,x4,x5 -> independent ALU pair.
    inst1 = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011);
    inst2 = enc_r(7'b0000000, 5'd5, 5'd4, 3'b100, 5'd6, 7'b0110011);
    expect_issue2(1'b1, "independent ALU pair");

    // add x3,x1,x2 ; xor x6,x3,x5 -> same-cycle RAW, block Issue2.
    inst2 = enc_r(7'b0000000, 5'd5, 5'd3, 3'b100, 5'd6, 7'b0110011);
    expect_issue2(1'b0, "RAW dependency");
    if (!raw_hazard) $fatal(1, "RAW dependency was not reported");

    // add x3,x1,x2 ; addi x3,x4,1 -> WAW, block Issue2.
    inst2 = enc_i(12'd1, 5'd4, 3'b000, 5'd3, 7'b0010011);
    expect_issue2(1'b0, "WAW dependency");
    if (!waw_hazard) $fatal(1, "WAW dependency was not reported");

    // lw x3,0(x1) ; add x6,x4,x5 -> asymmetric memory+ALU is allowed.
    inst1 = enc_i(12'd0, 5'd1, 3'b010, 5'd3, 7'b0000011);
    inst2 = enc_r(7'b0000000, 5'd5, 5'd4, 3'b000, 5'd6, 7'b0110011);
    expect_issue2(1'b1, "Issue1 load + Issue2 ALU");

    // lw x3,0(x1) ; add x6,x3,x5 -> load result dependency blocks Issue2.
    inst2 = enc_r(7'b0000000, 5'd5, 5'd3, 3'b000, 5'd6, 7'b0110011);
    expect_issue2(1'b0, "load-use RAW");

    // add ; lw in Issue2 -> unsupported in milestone 1.
    inst1 = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011);
    inst2 = enc_i(12'd0, 5'd4, 3'b010, 5'd6, 7'b0000011);
    expect_issue2(1'b0, "Issue2 load unsupported");
    if (!issue2_unsupported) $fatal(1, "Issue2 load should be unsupported");

    // add ; mul in Issue2 -> unsupported until secondary MUL/DSP lane exists.
    inst2 = enc_r(7'b0000001, 5'd5, 5'd4, 3'b000, 5'd6, 7'b0110011);
    expect_issue2(1'b0, "Issue2 MUL unsupported");

    // beq x1,x2,+imm ; add -> serialize until branch speculation is implemented.
    inst1 = 32'h00208063;
    inst2 = enc_r(7'b0000000, 5'd5, 5'd4, 3'b000, 5'd6, 7'b0110011);
    expect_issue2(1'b0, "branch serialization");
    if (!issue1_serializing) $fatal(1, "branch should serialize milestone-1 issue");

    // Missing second instruction never issues.
    inst1 = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011);
    inst2_valid = 1'b0;
    expect_issue2(1'b0, "invalid second instruction");

    $display("cv32e40p_dual_issue_idu_tb: PASS");
    $finish;
  end

endmodule
