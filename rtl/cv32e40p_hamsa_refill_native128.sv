// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Native 128-bit instruction-line refill engine for the HAMSA L0 frontend.
// The external interface transfers one complete 16-byte cache line per
// transaction. Requests are held until granted; the completed response is
// converted into a one-cycle refill_valid pulse for cv32e40p_hamsa_frontend.

module cv32e40p_hamsa_refill_native128 (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         flush_i,

    input  logic         miss_valid_i,
    input  logic [31:0]  miss_pc_i,
    output logic         miss_ready_o,

    output logic         line_req_o,
    output logic [31:0]  line_addr_o,
    input  logic         line_gnt_i,
    input  logic         line_rvalid_i,
    input  logic [127:0] line_rdata_i,

    output logic         refill_valid_o,
    output logic [31:0]  refill_addr_o,
    output logic [127:0] refill_data_o,
    output logic         busy_o
);

  typedef enum logic [1:0] {IDLE, REQ, WAIT_RSP} state_e;
  state_e state_q;
  logic [31:0] line_addr_q;

  assign busy_o       = (state_q != IDLE);
  assign miss_ready_o = (state_q == IDLE);
  assign line_req_o   = (state_q == REQ);
  assign line_addr_o  = line_addr_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q        <= IDLE;
      line_addr_q    <= '0;
      refill_valid_o <= 1'b0;
      refill_addr_o  <= '0;
      refill_data_o  <= '0;
    end else begin
      refill_valid_o <= 1'b0;

      if (flush_i) begin
        state_q <= IDLE;
      end else begin
        unique case (state_q)
          IDLE: begin
            if (miss_valid_i) begin
              line_addr_q <= {miss_pc_i[31:4], 4'b0000};
              state_q     <= REQ;
            end
          end

          REQ: begin
            if (line_gnt_i)
              state_q <= WAIT_RSP;
          end

          WAIT_RSP: begin
            if (line_rvalid_i) begin
              refill_addr_o  <= line_addr_q;
              refill_data_o  <= line_rdata_i;
              refill_valid_o <= 1'b1;
              state_q        <= IDLE;
            end
          end

          default: state_q <= IDLE;
        endcase
      end
    end
  end

endmodule
