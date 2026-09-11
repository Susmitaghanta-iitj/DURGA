// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// 5-read/3-write flip-flop register file for the asymmetric dual-issue
// CV32E40P/HAMSA prototype. Ports A/B/C and writes A/B are compatible with the
// original ID-stage RF. Ports D/E and write C are the secondary-issue additions.

module cv32e40p_register_file_5r3w #(
    parameter ADDR_WIDTH = 6,
    parameter DATA_WIDTH = 32,
    parameter FPU        = 0,
    parameter PULP_ZFINX = 0
) (
    input logic clk,
    input logic rst_n,
    input logic scan_cg_en_i,

    input logic [ADDR_WIDTH-1:0] raddr_a_i,
    output logic [DATA_WIDTH-1:0] rdata_a_o,
    input logic [ADDR_WIDTH-1:0] raddr_b_i,
    output logic [DATA_WIDTH-1:0] rdata_b_o,
    input logic [ADDR_WIDTH-1:0] raddr_c_i,
    output logic [DATA_WIDTH-1:0] rdata_c_o,
    input logic [ADDR_WIDTH-1:0] raddr_d_i,
    output logic [DATA_WIDTH-1:0] rdata_d_o,
    input logic [ADDR_WIDTH-1:0] raddr_e_i,
    output logic [DATA_WIDTH-1:0] rdata_e_o,

    input logic [ADDR_WIDTH-1:0] waddr_a_i,
    input logic [DATA_WIDTH-1:0] wdata_a_i,
    input logic                  we_a_i,
    input logic [ADDR_WIDTH-1:0] waddr_b_i,
    input logic [DATA_WIDTH-1:0] wdata_b_i,
    input logic                  we_b_i,
    input logic [ADDR_WIDTH-1:0] waddr_c_i,
    input logic [DATA_WIDTH-1:0] wdata_c_i,
    input logic                  we_c_i
);

  localparam int NUM_WORDS    = 32;
  localparam int NUM_FP_WORDS = 32;

  logic [NUM_WORDS-1:0][DATA_WIDTH-1:0] mem;
  logic [NUM_FP_WORDS-1:0][DATA_WIDTH-1:0] mem_fp;

  function automatic logic [DATA_WIDTH-1:0] read_port(
      input logic [ADDR_WIDTH-1:0] addr
  );
    if (addr[5]) read_port = mem_fp[addr[4:0]];
    else         read_port = mem[addr[4:0]];
  endfunction

  assign rdata_a_o = read_port(raddr_a_i);
  assign rdata_b_o = read_port(raddr_b_i);
  assign rdata_c_o = read_port(raddr_c_i);
  assign rdata_d_o = read_port(raddr_d_i);
  assign rdata_e_o = read_port(raddr_e_i);

  integer i;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < NUM_WORDS; i++) mem[i] <= '0;
    end else begin
      mem[0] <= '0;

      // W3 > W2 > W1 deterministic priority. Normal dual-issue operation has
      // no architectural WAW pair because the IDU rejects it.
      for (i = 1; i < NUM_WORDS; i++) begin
        if (we_c_i && !waddr_c_i[5] && (waddr_c_i[4:0] == i[4:0]))
          mem[i] <= wdata_c_i;
        else if (we_b_i && !waddr_b_i[5] && (waddr_b_i[4:0] == i[4:0]))
          mem[i] <= wdata_b_i;
        else if (we_a_i && !waddr_a_i[5] && (waddr_a_i[4:0] == i[4:0]))
          mem[i] <= wdata_a_i;
      end
    end
  end

  generate
    if (FPU && !PULP_ZFINX) begin : gen_fp
      integer f;
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (f = 0; f < NUM_FP_WORDS; f++) mem_fp[f] <= '0;
        end else begin
          for (f = 0; f < NUM_FP_WORDS; f++) begin
            if (we_c_i && waddr_c_i[5] && (waddr_c_i[4:0] == f[4:0]))
              mem_fp[f] <= wdata_c_i;
            else if (we_b_i && waddr_b_i[5] && (waddr_b_i[4:0] == f[4:0]))
              mem_fp[f] <= wdata_b_i;
            else if (we_a_i && waddr_a_i[5] && (waddr_a_i[4:0] == f[4:0]))
              mem_fp[f] <= wdata_a_i;
          end
        end
      end
    end else begin : gen_no_fp
      always_comb mem_fp = '0;
    end
  endgenerate

  // This FF implementation has no internal clock gates, so scan enable is
  // intentionally unused while keeping interface compatibility with the
  // baseline register file.
  logic unused_scan;
  assign unused_scan = scan_cg_en_i;

endmodule
