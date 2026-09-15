// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Shared SPARV instruction-line refill manager.
// Demand misses have priority over speculative next-line prefetches whenever
// the refill path is idle.  Once a transaction has started it is allowed to
// complete; redirects flush the transaction to preserve precise control flow.

module cv32e40p_sparv_refill_manager #(
    parameter bit NATIVE_128_REFILL = 1'b0
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         flush_i,

    input  logic         demand_valid_i,
    input  logic [31:0]  demand_pc_i,
    output logic         demand_accept_o,

    input  logic         prefetch_valid_i,
    input  logic [31:0]  prefetch_pc_i,
    output logic         prefetch_accept_o,

    output logic         instr_req_o,
    output logic [31:0]  instr_addr_o,
    input  logic         instr_gnt_i,
    input  logic         instr_rvalid_i,
    input  logic [31:0]  instr_rdata_i,

    output logic         line_req_o,
    output logic [31:0]  line_addr_o,
    input  logic         line_gnt_i,
    input  logic         line_rvalid_i,
    input  logic [127:0] line_rdata_i,

    output logic         refill_valid_o,
    output logic [31:0]  refill_addr_o,
    output logic [127:0] refill_data_o,
    output logic         refill_prefetch_o,
    output logic         busy_o
);

  logic selected_valid;
  logic [31:0] selected_pc;
  logic selected_prefetch;
  logic miss_ready;
  logic refill_valid_int;
  logic [31:0] refill_addr_int;
  logic [127:0] refill_data_int;
  logic refill_busy_int;
  logic source_prefetch_q;

  always_comb begin
    selected_valid    = 1'b0;
    selected_pc       = 32'd0;
    selected_prefetch = 1'b0;
    if (demand_valid_i) begin
      selected_valid = 1'b1;
      selected_pc    = demand_pc_i;
    end else if (prefetch_valid_i) begin
      selected_valid    = 1'b1;
      selected_pc       = prefetch_pc_i;
      selected_prefetch = 1'b1;
    end
  end

  assign demand_accept_o   = miss_ready && demand_valid_i;
  assign prefetch_accept_o = miss_ready && !demand_valid_i && prefetch_valid_i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      source_prefetch_q <= 1'b0;
    end else if (flush_i) begin
      source_prefetch_q <= 1'b0;
    end else if (miss_ready && selected_valid) begin
      source_prefetch_q <= selected_prefetch;
    end
  end

  generate
    if (!NATIVE_128_REFILL) begin : gen_refill32
      cv32e40p_hamsa_refill_32to128 refill_i (
          .clk            (clk),
          .rst_n          (rst_n),
          .flush_i        (flush_i),
          .miss_valid_i   (selected_valid),
          .miss_pc_i      (selected_pc),
          .miss_ready_o   (miss_ready),
          .instr_req_o    (instr_req_o),
          .instr_addr_o   (instr_addr_o),
          .instr_gnt_i    (instr_gnt_i),
          .instr_rvalid_i (instr_rvalid_i),
          .instr_rdata_i  (instr_rdata_i),
          .refill_valid_o (refill_valid_int),
          .refill_addr_o  (refill_addr_int),
          .refill_data_o  (refill_data_int),
          .busy_o         (refill_busy_int)
      );
      assign line_req_o  = 1'b0;
      assign line_addr_o = 32'd0;
    end else begin : gen_refill128
      cv32e40p_hamsa_refill_native128 refill_i (
          .clk            (clk),
          .rst_n          (rst_n),
          .flush_i        (flush_i),
          .miss_valid_i   (selected_valid),
          .miss_pc_i      (selected_pc),
          .miss_ready_o   (miss_ready),
          .line_req_o     (line_req_o),
          .line_addr_o    (line_addr_o),
          .line_gnt_i     (line_gnt_i),
          .line_rvalid_i  (line_rvalid_i),
          .line_rdata_i   (line_rdata_i),
          .refill_valid_o (refill_valid_int),
          .refill_addr_o  (refill_addr_int),
          .refill_data_o  (refill_data_int),
          .busy_o         (refill_busy_int)
      );
      assign instr_req_o  = 1'b0;
      assign instr_addr_o = 32'd0;
    end
  endgenerate

  assign refill_valid_o    = refill_valid_int;
  assign refill_addr_o     = refill_addr_int;
  assign refill_data_o     = refill_data_int;
  assign refill_prefetch_o = refill_valid_int && source_prefetch_q;
  assign busy_o            = refill_busy_int;

endmodule
