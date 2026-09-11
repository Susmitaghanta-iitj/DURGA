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

    inst1 = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011);
    inst2 = enc_r(7'b0000000, 5'd5, 5'd4, 3'b100, 5'd6, 7'b0110011);
    expect_issue2(1'b1, "independent ALU pair");

    inst2 = enc_r(7'b0000000, 5'd5, 5'd3, 3'b100, 5'd6, 7'b0110011);
    expect_issue2(1'b0, "RAW dependency");
    if (!raw_hazard) $fatal(1, "RAW dependency was not reported");

    inst2 = enc_i(12'd1, 5'd4, 3'b000, 5'd3, 7'b0010011);
    expect_issue2(1'b0, "WAW dependency");
    if (!waw_hazard) $fatal(1, "WAW dependency was not reported");

    inst1 = enc_i(12'd0, 5'd1, 3'b010, 5'd3, 7'b0000011);
    inst2 = enc_r(7'b0000000, 5'd5, 5'd4, 3'b000, 5'd6, 7'b0110011);
    expect_issue2(1'b1, "Issue1 load + Issue2 ALU");

    inst2 = enc_r(7'b0000000, 5'd5, 5'd3, 3'b000, 5'd6, 7'b0110011);
    expect_issue2(1'b0, "load-use RAW");

    inst1 = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011);
    inst2 = enc_i(12'd0, 5'd4, 3'b010, 5'd6, 7'b0000011);
    expect_issue2(1'b0, "Issue2 load unsupported");
    if (!issue2_unsupported) $fatal(1, "Issue2 load should be unsupported");

    // MUL is now part of the compact Issue2 RV32M subset.
    inst2 = enc_r(7'b0000001, 5'd5, 5'd4, 3'b000, 5'd6, 7'b0110011);
    expect_issue2(1'b1, "Issue2 MUL supported");

    // DIV remains unsupported.
    inst2 = enc_r(7'b0000001, 5'd5, 5'd4, 3'b100, 5'd6, 7'b0110011);
    expect_issue2(1'b0, "Issue2 DIV unsupported");

    // Default IDU instance remains conservative behind branches. The HAMSA
    // issue cluster enables SPECULATE_BEHIND_BRANCH and relies on recovery kill.
    inst1 = 32'h00208063;
    inst2 = enc_r(7'b0000000, 5'd5, 5'd4, 3'b000, 5'd6, 7'b0110011);
    expect_issue2(1'b0, "branch serialization");
    if (!issue1_serializing) $fatal(1, "default branch policy should serialize");

    // Unknown/custom Issue1 must serialize conservatively.
    inst1 = 32'h0000000b;
    inst2 = enc_r(7'b0000000, 5'd5, 5'd4, 3'b000, 5'd6, 7'b0110011);
    expect_issue2(1'b0, "unknown Issue1 serialization");
    if (!issue1_serializing) $fatal(1, "unknown Issue1 should serialize");

    inst1 = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011);
    inst2_valid = 1'b0;
    expect_issue2(1'b0, "invalid second instruction");

    $display("cv32e40p_dual_issue_idu_tb: PASS");
    $finish;
  end

endmodule
