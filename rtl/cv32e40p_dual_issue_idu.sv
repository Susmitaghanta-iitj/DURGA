// Copyright 2026
//
// Licensed under the Solderpad Hardware License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://solderpad.org/licenses/
//
// Lightweight asymmetric dual-issue decision unit for CV32E40P.
//
// Milestone-1 policy:
//   * Issue1 remains the full CV32E40P pipeline.
//   * Issue2 accepts only RV32 integer ALU OP/OP-IMM instructions.
//   * Memory, CSR, control-flow, fence and custom instructions are kept on Issue1.
//   * Same-cycle RAW and WAW hazards from Issue1 -> Issue2 block Issue2.
//   * Conditional-branch speculation is intentionally deferred to a later milestone.
//
// This block performs only the partial decode required to decide whether the
// second sequential instruction can be issued safely. It does not replace the
// architectural decoder.

module cv32e40p_dual_issue_idu (
    input  logic        inst1_valid_i,
    input  logic [31:0] inst1_i,
    input  logic        inst2_valid_i,
    input  logic [31:0] inst2_i,

    output logic        issue1_valid_o,
    output logic        issue2_valid_o,

    output logic        raw_hazard_o,
    output logic        waw_hazard_o,
    output logic        issue2_unsupported_o,
    output logic        issue1_serializing_o,

    output logic [4:0]  inst1_rd_o,
    output logic [4:0]  inst2_rs1_o,
    output logic [4:0]  inst2_rs2_o,
    output logic [4:0]  inst2_rd_o
);

  // Base RISC-V opcodes used by the partial decoder.
  localparam logic [6:0] OPC_LOAD     = 7'b0000011;
  localparam logic [6:0] OPC_MISC_MEM = 7'b0001111;
  localparam logic [6:0] OPC_OP_IMM   = 7'b0010011;
  localparam logic [6:0] OPC_AUIPC    = 7'b0010111;
  localparam logic [6:0] OPC_STORE    = 7'b0100011;
  localparam logic [6:0] OPC_OP       = 7'b0110011;
  localparam logic [6:0] OPC_LUI      = 7'b0110111;
  localparam logic [6:0] OPC_BRANCH   = 7'b1100011;
  localparam logic [6:0] OPC_JALR     = 7'b1100111;
  localparam logic [6:0] OPC_JAL      = 7'b1101111;
  localparam logic [6:0] OPC_SYSTEM   = 7'b1110011;

  logic [6:0] opcode1;
  logic [6:0] opcode2;

  logic       inst1_writes_rd;
  logic       inst2_writes_rd;
  logic       inst2_uses_rs1;
  logic       inst2_uses_rs2;
  logic       issue2_class_supported;

  assign opcode1    = inst1_i[6:0];
  assign opcode2    = inst2_i[6:0];

  assign inst1_rd_o = inst1_i[11:7];
  assign inst2_rd_o = inst2_i[11:7];
  assign inst2_rs1_o = inst2_i[19:15];
  assign inst2_rs2_o = inst2_i[24:20];

  // Determine whether Issue1 produces an architectural integer destination.
  // Custom/PULP instructions are conservatively excluded from same-cycle issue
  // until the existing CV32E40P decoder is connected to the IDU.
  always_comb begin
    inst1_writes_rd = 1'b0;
    unique case (opcode1)
      OPC_LOAD,
      OPC_OP_IMM,
      OPC_AUIPC,
      OPC_OP,
      OPC_LUI,
      OPC_JALR,
      OPC_JAL: inst1_writes_rd = (inst1_rd_o != 5'd0);
      default: inst1_writes_rd = 1'b0;
    endcase
  end

  // Milestone-1 secondary lane: regular RV32 integer ALU instructions only.
  // M-extension instructions share OPC_OP; funct7=0000001 is deliberately
  // rejected until the secondary multiplier/DSP path is implemented.
  always_comb begin
    issue2_class_supported = 1'b0;
    inst2_uses_rs1         = 1'b0;
    inst2_uses_rs2         = 1'b0;
    inst2_writes_rd        = 1'b0;

    unique case (opcode2)
      OPC_OP_IMM: begin
        issue2_class_supported = 1'b1;
        inst2_uses_rs1         = 1'b1;
        inst2_uses_rs2         = 1'b0;
        inst2_writes_rd        = (inst2_rd_o != 5'd0);
      end

      OPC_OP: begin
        // funct7 == 0000001 identifies MUL/DIV in RV32M.
        issue2_class_supported = (inst2_i[31:25] != 7'b0000001);
        inst2_uses_rs1         = 1'b1;
        inst2_uses_rs2         = 1'b1;
        inst2_writes_rd        = (inst2_rd_o != 5'd0);
      end

      default: begin
        issue2_class_supported = 1'b0;
      end
    endcase
  end

  // Until branch speculation is added, control/system/fence instructions in
  // Issue1 serialize the pair. Loads/stores are intentionally NOT serializing:
  // HAMSA-style asymmetric issue allows memory on Issue1 + integer ALU on Issue2.
  always_comb begin
    unique case (opcode1)
      OPC_BRANCH,
      OPC_JALR,
      OPC_JAL,
      OPC_SYSTEM,
      OPC_MISC_MEM: issue1_serializing_o = 1'b1;
      default:      issue1_serializing_o = 1'b0;
    endcase
  end

  assign raw_hazard_o = inst1_writes_rd &&
                        (((inst1_rd_o == inst2_rs1_o) && inst2_uses_rs1) ||
                         ((inst1_rd_o == inst2_rs2_o) && inst2_uses_rs2));

  assign waw_hazard_o = inst1_writes_rd && inst2_writes_rd &&
                        (inst1_rd_o == inst2_rd_o);

  assign issue2_unsupported_o = !issue2_class_supported;

  // Issue1 preserves baseline behavior. Issue2 is opportunistic and must never
  // prevent the older instruction from making progress.
  assign issue1_valid_o = inst1_valid_i;
  assign issue2_valid_o = inst1_valid_i && inst2_valid_i &&
                          issue2_class_supported &&
                          !issue1_serializing_o &&
                          !raw_hazard_o &&
                          !waw_hazard_o;

  // Keep currently-unused opcode constants visible to lint and future extension
  // work without changing the conservative Milestone-1 policy.
  logic unused_opcode_refs;
  assign unused_opcode_refs = (opcode1 == OPC_STORE) || (opcode2 == OPC_LOAD) ||
                              (opcode2 == OPC_STORE) || (opcode2 == OPC_AUIPC) ||
                              (opcode2 == OPC_LUI);

endmodule
