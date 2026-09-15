`timescale 1ns/1ps
module cv32e40p_sparv_mac_dotp_ref_tb;
  logic [31:0] operand_a_i, operand_b_i;
  logic [63:0] accumulator_i;
  logic [1:0] simd_mode_i;
  logic signed_a_i, signed_b_i, accumulate_i;
  logic [63:0] result_o;

  cv32e40p_sparv_mac_dotp_ref dut(.*);
  task expect64(input logic [63:0] got,input logic [63:0] exp,input string msg);
    begin if(got!==exp) begin $display("FAIL %s got=%h exp=%h",msg,got,exp); $fatal(1); end end
  endtask

  initial begin
    accumulator_i=0; signed_a_i=0; signed_b_i=0; accumulate_i=0;
    // 4x8 unsigned: (1*5)+(2*6)+(3*7)+(4*8)=70
    simd_mode_i=2'b00; operand_a_i=32'h04030201; operand_b_i=32'h08070605; #1;
    expect64(result_o,64'd70,"4x8 unsigned dot");

    // 2x16 signed: (-2*3)+(4*-5)=-26
    signed_a_i=1; signed_b_i=1; simd_mode_i=2'b01;
    operand_a_i={16'd4,16'hfffe}; operand_b_i={16'hfffb,16'd3}; #1;
    expect64(result_o,$unsigned(-64'sd26),"2x16 signed dot");

    // 1x32 MAC: 7*9 + 11 = 74
    simd_mode_i=2'b10; operand_a_i=32'd7; operand_b_i=32'd9;
    signed_a_i=0; signed_b_i=0; accumulate_i=1; accumulator_i=64'd11; #1;
    expect64(result_o,64'd74,"1x32 MAC");

    $display("PASS: SPARV MAC/DOTP reference");
    $finish;
  end
endmodule
