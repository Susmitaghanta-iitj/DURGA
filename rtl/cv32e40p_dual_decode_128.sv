// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Extracts and decompresses up to two sequential RISC-V instructions from one
// 128-bit L0 line. Instructions are indexed at 16-bit granularity. If either
// 32-bit instruction would cross the 128-bit line boundary, the corresponding
// output is marked invalid so the frontend can refill/use the next line.

module cv32e40p_dual_decode_128 #(
    parameter FPU = 0
) (
    input  logic [127:0] line_i,
    input  logic [2:0]   halfword_index_i,
    input  logic         line_valid_i,

    output logic         inst1_valid_o,
    output logic [31:0]  inst1_o,
    output logic         inst1_compressed_o,
    output logic         inst1_illegal_c_o,
    output logic [2:0]   inst1_halfwords_o,

    output logic         inst2_valid_o,
    output logic [31:0]  inst2_o,
    output logic         inst2_compressed_o,
    output logic         inst2_illegal_c_o,
    output logic [2:0]   inst2_halfwords_o
);

  logic [15:0] hw [0:7];
  logic [31:0] raw1, raw2;
  logic        c1, c2;
  logic [3:0]  idx2;
  integer i;

  always_comb begin
    for (i = 0; i < 8; i++) hw[i] = line_i[i*16 +: 16];

    c1 = (hw[halfword_index_i][1:0] != 2'b11);
    raw1 = 32'd0;
    inst1_valid_o = line_valid_i;
    if (c1) begin
      raw1 = {16'd0, hw[halfword_index_i]};
    end else if (halfword_index_i != 3'd7) begin
      raw1 = {hw[halfword_index_i + 3'd1], hw[halfword_index_i]};
    end else begin
      inst1_valid_o = 1'b0;
    end

    inst1_halfwords_o = c1 ? 3'd1 : 3'd2;
    idx2 = {1'b0, halfword_index_i} + (c1 ? 4'd1 : 4'd2);

    raw2 = 32'd0;
    c2 = 1'b0;
    inst2_valid_o = 1'b0;
    inst2_halfwords_o = 3'd0;

    if (inst1_valid_o && idx2 < 8) begin
      c2 = (hw[idx2[2:0]][1:0] != 2'b11);
      if (c2) begin
        raw2 = {16'd0, hw[idx2[2:0]]};
        inst2_valid_o = 1'b1;
        inst2_halfwords_o = 3'd1;
      end else if (idx2 < 7) begin
        raw2 = {hw[idx2[2:0] + 3'd1], hw[idx2[2:0]]};
        inst2_valid_o = 1'b1;
        inst2_halfwords_o = 3'd2;
      end
    end
  end

  cv32e40p_compressed_decoder #(.FPU(FPU)) dec1_i (
      .instr_i(raw1),
      .instr_o(inst1_o),
      .is_compressed_o(inst1_compressed_o),
      .illegal_instr_o(inst1_illegal_c_o)
  );

  cv32e40p_compressed_decoder #(.FPU(FPU)) dec2_i (
      .instr_i(raw2),
      .instr_o(inst2_o),
      .is_compressed_o(inst2_compressed_o),
      .illegal_instr_o(inst2_illegal_c_o)
  );

endmodule
