// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Cross-lane forwarding helper for the asymmetric dual-issue prototype.
// Priority is youngest producer first: EX2, EX1, WB2, WB1, then RF data.
// x0 is never forwarded.

module cv32e40p_dual_issue_forwarding (
    input  logic [4:0]  rs1_i,
    input  logic [4:0]  rs2_i,
    input  logic [31:0] rs1_rf_i,
    input  logic [31:0] rs2_rf_i,

    input  logic        ex1_we_i,
    input  logic [4:0]  ex1_rd_i,
    input  logic [31:0] ex1_data_i,
    input  logic        ex2_we_i,
    input  logic [4:0]  ex2_rd_i,
    input  logic [31:0] ex2_data_i,
    input  logic        wb1_we_i,
    input  logic [4:0]  wb1_rd_i,
    input  logic [31:0] wb1_data_i,
    input  logic        wb2_we_i,
    input  logic [4:0]  wb2_rd_i,
    input  logic [31:0] wb2_data_i,

    output logic [31:0] rs1_o,
    output logic [31:0] rs2_o,
    output logic        rs1_forwarded_o,
    output logic        rs2_forwarded_o
);

  function automatic logic hit(input logic we, input logic [4:0] rd, input logic [4:0] rs);
    hit = we && (rd != 5'd0) && (rd == rs);
  endfunction

  always_comb begin
    rs1_o           = rs1_rf_i;
    rs1_forwarded_o = 1'b0;
    if (hit(wb1_we_i, wb1_rd_i, rs1_i)) begin
      rs1_o           = wb1_data_i;
      rs1_forwarded_o = 1'b1;
    end
    if (hit(wb2_we_i, wb2_rd_i, rs1_i)) begin
      rs1_o           = wb2_data_i;
      rs1_forwarded_o = 1'b1;
    end
    if (hit(ex1_we_i, ex1_rd_i, rs1_i)) begin
      rs1_o           = ex1_data_i;
      rs1_forwarded_o = 1'b1;
    end
    if (hit(ex2_we_i, ex2_rd_i, rs1_i)) begin
      rs1_o           = ex2_data_i;
      rs1_forwarded_o = 1'b1;
    end
    if (rs1_i == 5'd0) begin
      rs1_o           = 32'd0;
      rs1_forwarded_o = 1'b0;
    end
  end

  always_comb begin
    rs2_o           = rs2_rf_i;
    rs2_forwarded_o = 1'b0;
    if (hit(wb1_we_i, wb1_rd_i, rs2_i)) begin
      rs2_o           = wb1_data_i;
      rs2_forwarded_o = 1'b1;
    end
    if (hit(wb2_we_i, wb2_rd_i, rs2_i)) begin
      rs2_o           = wb2_data_i;
      rs2_forwarded_o = 1'b1;
    end
    if (hit(ex1_we_i, ex1_rd_i, rs2_i)) begin
      rs2_o           = ex1_data_i;
      rs2_forwarded_o = 1'b1;
    end
    if (hit(ex2_we_i, ex2_rd_i, rs2_i)) begin
      rs2_o           = ex2_data_i;
      rs2_forwarded_o = 1'b1;
    end
    if (rs2_i == 5'd0) begin
      rs2_o           = 32'd0;
      rs2_forwarded_o = 1'b0;
    end
  end

endmodule
