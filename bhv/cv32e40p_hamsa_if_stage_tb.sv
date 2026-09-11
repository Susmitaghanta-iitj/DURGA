`timescale 1ns/1ps

module cv32e40p_hamsa_if_stage_tb;
  import cv32e40p_pkg::*;

  logic clk = 0;
  logic rst_n = 0;
  logic req;
  logic instr_req;
  logic [31:0] instr_addr;
  logic instr_gnt, instr_rvalid;
  logic [31:0] instr_rdata;
  logic line_req;
  logic [31:0] line_addr;
  logic line_gnt, line_rvalid;
  logic [127:0] line_rdata;
  logic instr_valid;
  logic [31:0] instr;
  logic is_c, illegal_c;
  logic [31:0] pc_if, pc_id;
  logic fetch_failed;
  logic inst2_valid;
  logic [31:0] inst2;
  logic [31:0] inst2_pc;
  logic inst2_c, inst2_illegal;
  logic inst2_consumed;
  logic clear_valid, pc_set;
  logic [3:0] pc_mux;
  logic id_ready;
  logic if_busy, perf_imiss;
  logic csr_mtvec_init;
  logic l0_lookup, l0_hit, l0_refill;

  always #5 clk = ~clk;

  cv32e40p_hamsa_if_stage #(
      .PULP_XPULP(0), .PULP_SECURE(0), .FPU(0), .L0_LINES(8),
      .NATIVE_128_REFILL(1'b1)
  ) dut (
      .clk(clk), .rst_n(rst_n),
      .m_trap_base_addr_i(24'h000100), .u_trap_base_addr_i(24'h000200),
      .trap_addr_mux_i(TRAP_MACHINE), .boot_addr_i(32'h00000180),
      .dm_exception_addr_i(32'h00000800), .dm_halt_addr_i(32'h00000900),
      .req_i(req),
      .instr_req_o(instr_req), .instr_addr_o(instr_addr),
      .instr_gnt_i(instr_gnt), .instr_rvalid_i(instr_rvalid),
      .instr_rdata_i(instr_rdata), .instr_err_i(1'b0), .instr_err_pmp_i(1'b0),
      .line_req_o(line_req), .line_addr_o(line_addr),
      .line_gnt_i(line_gnt), .line_rvalid_i(line_rvalid), .line_rdata_i(line_rdata),
      .instr_valid_id_o(instr_valid), .instr_rdata_id_o(instr),
      .is_compressed_id_o(is_c), .illegal_c_insn_id_o(illegal_c),
      .pc_if_o(pc_if), .pc_id_o(pc_id), .is_fetch_failed_o(fetch_failed),
      .inst2_valid_o(inst2_valid), .inst2_rdata_o(inst2), .inst2_pc_o(inst2_pc),
      .inst2_compressed_o(inst2_c), .inst2_illegal_c_o(inst2_illegal),
      .inst2_consumed_i(inst2_consumed),
      .clear_instr_valid_i(clear_valid), .pc_set_i(pc_set),
      .mepc_i(32'h00000300), .uepc_i(32'h00000400), .depc_i(32'h00000500),
      .pc_mux_i(pc_mux), .exc_pc_mux_i(EXC_PC_EXCEPTION),
      .m_exc_vec_pc_mux_i(5'd0), .u_exc_vec_pc_mux_i(5'd0),
      .csr_mtvec_init_o(csr_mtvec_init),
      .jump_target_id_i(32'h00000200), .jump_target_ex_i(32'h00000240),
      .hwlp_jump_i(1'b0), .hwlp_target_i(32'h0),
      .halt_if_i(1'b0), .id_ready_i(id_ready),
      .if_busy_o(if_busy), .perf_imiss_o(perf_imiss),
      .l0_lookup_o(l0_lookup), .l0_hit_o(l0_hit), .l0_refill_o(l0_refill)
  );

  task automatic check(input logic cond, input string msg);
    if (!cond) begin
      $display("FAIL: %s", msg);
      $fatal(1);
    end
  endtask

  task automatic service_line(input logic [31:0] expected_addr,
                              input logic [127:0] data);
    integer guard;
    begin
      guard = 0;
      while (!line_req && guard < 30) begin
        @(posedge clk);
        guard++;
      end
      check(line_req, "timed out waiting for line request");
      check(line_addr == expected_addr, "unexpected native line address");
      line_gnt = 1;
      @(posedge clk);
      line_gnt = 0;
      line_rdata = data;
      line_rvalid = 1;
      @(posedge clk);
      line_rvalid = 0;
    end
  endtask

  task automatic wait_pair(input logic [31:0] expected_pc1,
                           input logic [31:0] expected_pc2);
    integer guard;
    begin
      guard = 0;
      while (!instr_valid && guard < 30) begin
        @(posedge clk);
        guard++;
      end
      check(instr_valid, "timed out waiting for decoded pair");
      check(pc_id == expected_pc1, "primary PC mismatch");
      check(inst2_valid, "second instruction should be valid");
      check(inst2_pc == expected_pc2, "secondary PC mismatch");
      check(!is_c && !inst2_c, "test line should contain uncompressed instructions");
    end
  endtask

  localparam logic [31:0] I1 = 32'h00100093;
  localparam logic [31:0] I2 = 32'h00200113;
  localparam logic [31:0] I3 = 32'h00300193;
  localparam logic [31:0] I4 = 32'h00400213;

  initial begin
    req = 0;
    instr_gnt = 0;
    instr_rvalid = 0;
    instr_rdata = 0;
    line_gnt = 0;
    line_rvalid = 0;
    line_rdata = 0;
    inst2_consumed = 0;
    clear_valid = 0;
    pc_set = 0;
    pc_mux = PC_BOOT;
    id_ready = 0;

    repeat (3) @(posedge clk);
    rst_n = 1;
    req = 1;

    service_line(32'h00000180, {I4, I3, I2, I1});
    wait_pair(32'h00000180, 32'h00000184);
    check(instr == I1 && inst2 == I2, "first decoded pair mismatch");

    inst2_consumed = 0;
    id_ready = 1;
    @(posedge clk);
    id_ready = 0;
    wait_pair(32'h00000184, 32'h00000188);
    check(instr == I2 && inst2 == I3, "replayed pair mismatch");

    inst2_consumed = 1;
    id_ready = 1;
    @(posedge clk);
    id_ready = 0;
    begin : wait_i4
      integer guard;
      guard = 0;
      while ((!instr_valid || pc_id != 32'h0000018c) && guard < 30) begin
        @(posedge clk);
        guard++;
      end
      check(instr_valid && pc_id == 32'h0000018c, "consumed pair did not advance to I4");
      check(instr == I4, "I4 instruction mismatch");
    end

    pc_mux = PC_JUMP;
    pc_set = 1;
    @(posedge clk);
    pc_set = 0;
    pc_mux = PC_BOOT;
    id_ready = 0;
    service_line(32'h00000200, {I4, I3, I2, I1});
    wait_pair(32'h00000200, 32'h00000204);
    check(instr == I1, "redirected primary instruction mismatch");

    $display("PASS: H2 full-core IF replay/redirect behavior");
    $finish;
  end
endmodule
