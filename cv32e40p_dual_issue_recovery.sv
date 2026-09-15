// Copyright 2026
// Licensed under the Solderpad Hardware License, Version 2.0.
//
// Recovery helper for the asymmetric dual-issue lane. A redirect caused by
// Issue1 invalidates any younger Issue2 operation and requests frontend flush.

module cv32e40p_dual_issue_recovery (
    input  logic issue2_inflight_i,
    input  logic branch_in_ex_i,
    input  logic branch_taken_i,
    input  logic jump_redirect_i,
    input  logic exception_redirect_i,
    input  logic debug_redirect_i,
    output logic kill_issue2_o,
    output logic flush_pair_buffer_o
);

  logic redirect;

  assign redirect = (branch_in_ex_i && branch_taken_i) ||
                    jump_redirect_i || exception_redirect_i || debug_redirect_i;

  assign kill_issue2_o      = issue2_inflight_i && redirect;
  assign flush_pair_buffer_o = redirect;

endmodule
