// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Four-beat 32-bit instruction-bus refill engine for the HAMSA 128-bit L0.
// This adapter lets the 128-bit frontend be exercised on the existing CV32E40P
// instruction interface. It is a functional compatibility path: the external
// bus still transfers 32 bits per beat, so it does NOT model a native 128-bit
// memory datapath. A future SoC integration may replace this block with one
// native 128-bit refill transaction without changing the L0/frontend.

module cv32e40p_hamsa_refill_32to128 (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         flush_i,

    input  logic         miss_valid_i,
    input  logic [31:0]  miss_pc_i,
    output logic         miss_ready_o,

    output logic         instr_req_o,
    output logic [31:0]  instr_addr_o,
    input  logic         instr_gnt_i,
    input  logic         instr_rvalid_i,
    input  logic [31:0]  instr_rdata_i,

    output logic         refill_valid_o,
    output logic [31:0]  refill_addr_o,
    output logic [127:0] refill_data_o,
    output logic         busy_o
);

  typedef enum logic [1:0] {IDLE, REQ, WAIT_RSP} state_e;
  state_e state_q;

  logic [31:0] line_addr_q;
  logic [1:0]  beat_q;
  logic [127:0] line_q;

  assign busy_o       = (state_q != IDLE);
  assign miss_ready_o = (state_q == IDLE);
  assign instr_req_o  = (state_q == REQ);
  assign instr_addr_o = line_addr_q + {28'd0, beat_q, 2'b00};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q         <= IDLE;
      line_addr_q     <= '0;
      beat_q          <= '0;
      line_q          <= '0;
      refill_valid_o  <= 1'b0;
      refill_addr_o   <= '0;
      refill_data_o   <= '0;
    end else begin
      refill_valid_o <= 1'b0;

      if (flush_i) begin
        state_q <= IDLE;
        beat_q  <= '0;
      end else begin
        unique case (state_q)
          IDLE: begin
            if (miss_valid_i) begin
              line_addr_q <= {miss_pc_i[31:4], 4'b0000};
              beat_q      <= 2'd0;
              line_q      <= '0;
              state_q     <= REQ;
            end
          end

          REQ: begin
            if (instr_gnt_i)
              state_q <= WAIT_RSP;
          end

          WAIT_RSP: begin
            if (instr_rvalid_i) begin
              unique case (beat_q)
                2'd0: line_q[31:0]    <= instr_rdata_i;
                2'd1: line_q[63:32]   <= instr_rdata_i;
                2'd2: line_q[95:64]   <= instr_rdata_i;
                2'd3: line_q[127:96]  <= instr_rdata_i;
              endcase

              if (beat_q == 2'd3) begin
                // Nonblocking assignments update line_q after this clock edge,
                // so explicitly construct the completed line for the pulse.
                refill_data_o  <= {instr_rdata_i, line_q[95:0]};
                refill_addr_o  <= line_addr_q;
                refill_valid_o <= 1'b1;
                state_q        <= IDLE;
                beat_q         <= '0;
              end else begin
                beat_q  <= beat_q + 2'd1;
                state_q <= REQ;
              end
            end
          end

          default: state_q <= IDLE;
        endcase
      end
    end
  end

endmodule
