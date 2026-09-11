module cv32e40p_dual_issue_forwarding_tb;
  logic [4:0] rs1, rs2;
  logic [31:0] rs1_rf, rs2_rf;
  logic ex1_we, ex2_we, wb1_we, wb2_we;
  logic [4:0] ex1_rd, ex2_rd, wb1_rd, wb2_rd;
  logic [31:0] ex1_data, ex2_data, wb1_data, wb2_data;
  logic [31:0] rs1_out, rs2_out;
  logic rs1_fwd, rs2_fwd;

  cv32e40p_dual_issue_forwarding dut (
    .rs1_i(rs1), .rs2_i(rs2), .rs1_rf_i(rs1_rf), .rs2_rf_i(rs2_rf),
    .ex1_we_i(ex1_we), .ex1_rd_i(ex1_rd), .ex1_data_i(ex1_data),
    .ex2_we_i(ex2_we), .ex2_rd_i(ex2_rd), .ex2_data_i(ex2_data),
    .wb1_we_i(wb1_we), .wb1_rd_i(wb1_rd), .wb1_data_i(wb1_data),
    .wb2_we_i(wb2_we), .wb2_rd_i(wb2_rd), .wb2_data_i(wb2_data),
    .rs1_o(rs1_out), .rs2_o(rs2_out),
    .rs1_forwarded_o(rs1_fwd), .rs2_forwarded_o(rs2_fwd)
  );

  initial begin
    rs1=5'd1; rs2=5'd2; rs1_rf=32'h11; rs2_rf=32'h22;
    ex1_we=0; ex2_we=0; wb1_we=0; wb2_we=0;
    ex1_rd=0; ex2_rd=0; wb1_rd=0; wb2_rd=0;
    ex1_data=0; ex2_data=0; wb1_data=0; wb2_data=0;
    #1;
    if (rs1_out!==32'h11 || rs2_out!==32'h22) $fatal(1,"RF fallback failed");

    wb1_we=1; wb1_rd=5'd1; wb1_data=32'hAAAA;
    ex1_we=1; ex1_rd=5'd1; ex1_data=32'hBBBB;
    ex2_we=1; ex2_rd=5'd1; ex2_data=32'hCCCC;
    #1;
    if (rs1_out!==32'hCCCC || !rs1_fwd) $fatal(1,"youngest forwarding priority failed");

    rs2=5'd0; ex2_we=1; ex2_rd=5'd0; ex2_data=32'hFFFF_FFFF;
    #1;
    if (rs2_out!==32'd0 || rs2_fwd) $fatal(1,"x0 forwarding rule failed");

    $display("cv32e40p_dual_issue_forwarding_tb: PASS");
    $finish;
  end
endmodule
