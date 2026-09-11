// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Restricted decoder for the asymmetric secondary issue lane.
// Supports RV32I OP/OP-IMM plus scalar RV32M MUL. Other RV32M operations stay
// on Issue1 to keep the secondary lane compact and single-cycle.

module cv32e40p_issue2_decoder
  import cv32e40p_pkg::*;
(
    input  logic        valid_i,
    input  logic [31:0] instr_i,
    input  logic [31:0] rs1_data_i,
    input  logic [31:0] rs2_data_i,

    output logic        valid_o,
    output logic        illegal_o,
    output logic [4:0]  rd_o,
    output alu_opcode_e alu_operator_o,
    output logic        mul_en_o,
    output logic [31:0] operand_a_o,
    output logic [31:0] operand_b_o
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [31:0] imm_i;

  assign opcode = instr_i[6:0];
  assign funct3 = instr_i[14:12];
  assign funct7 = instr_i[31:25];
  assign rd_o   = instr_i[11:7];
  assign imm_i  = {{20{instr_i[31]}}, instr_i[31:20]};

  always_comb begin
    valid_o        = valid_i;
    illegal_o      = 1'b0;
    alu_operator_o = ALU_ADD;
    mul_en_o       = 1'b0;
    operand_a_o    = rs1_data_i;
    operand_b_o    = rs2_data_i;

    if (valid_i) begin
      unique case (opcode)
        OPCODE_OPIMM: begin
          operand_b_o = imm_i;
          unique case (funct3)
            3'b000: alu_operator_o = ALU_ADD;   // ADDI
            3'b010: alu_operator_o = ALU_SLTS;  // SLTI
            3'b011: alu_operator_o = ALU_SLTU;  // SLTIU
            3'b100: alu_operator_o = ALU_XOR;   // XORI
            3'b110: alu_operator_o = ALU_OR;    // ORI
            3'b111: alu_operator_o = ALU_AND;   // ANDI

            3'b001: begin                       // SLLI
              if (funct7 == 7'b0000000) begin
                alu_operator_o = ALU_SLL;
                operand_b_o    = {27'b0, instr_i[24:20]};
              end else begin
                illegal_o = 1'b1;
              end
            end

            3'b101: begin                       // SRLI / SRAI
              operand_b_o = {27'b0, instr_i[24:20]};
              unique case (funct7)
                7'b0000000: alu_operator_o = ALU_SRL;
                7'b0100000: alu_operator_o = ALU_SRA;
                default:    illegal_o = 1'b1;
              endcase
            end

            default: illegal_o = 1'b1;
          endcase
        end

        OPCODE_OP: begin
          if (funct7 == 7'b0000001) begin
            // Compact secondary RV32M subset: MUL only.
            if (funct3 == 3'b000) mul_en_o = 1'b1;
            else illegal_o = 1'b1;
          end else begin
            unique case (funct3)
              3'b000: begin                     // ADD / SUB
                unique case (funct7)
                  7'b0000000: alu_operator_o = ALU_ADD;
                  7'b0100000: alu_operator_o = ALU_SUB;
                  default:    illegal_o = 1'b1;
                endcase
              end
              3'b001: begin                     // SLL
                alu_operator_o = ALU_SLL;
                if (funct7 != 7'b0000000) illegal_o = 1'b1;
              end
              3'b010: begin                     // SLT
                alu_operator_o = ALU_SLTS;
                if (funct7 != 7'b0000000) illegal_o = 1'b1;
              end
              3'b011: begin                     // SLTU
                alu_operator_o = ALU_SLTU;
                if (funct7 != 7'b0000000) illegal_o = 1'b1;
              end
              3'b100: begin                     // XOR
                alu_operator_o = ALU_XOR;
                if (funct7 != 7'b0000000) illegal_o = 1'b1;
              end
              3'b101: begin                     // SRL / SRA
                unique case (funct7)
                  7'b0000000: alu_operator_o = ALU_SRL;
                  7'b0100000: alu_operator_o = ALU_SRA;
                  default:    illegal_o = 1'b1;
                endcase
              end
              3'b110: begin                     // OR
                alu_operator_o = ALU_OR;
                if (funct7 != 7'b0000000) illegal_o = 1'b1;
              end
              3'b111: begin                     // AND
                alu_operator_o = ALU_AND;
                if (funct7 != 7'b0000000) illegal_o = 1'b1;
              end
              default: illegal_o = 1'b1;
            endcase
          end
        end

        default: illegal_o = 1'b1;
      endcase
    end

    if (illegal_o) valid_o = 1'b0;
  end

endmodule
