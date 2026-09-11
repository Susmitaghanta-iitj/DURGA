# CV32E40P asymmetric dual-issue development

This branch develops a HAMSA-DI-inspired asymmetric dual-issue extension while
preserving CV32E40P single-issue behavior as the architectural reference.

## Design rule

Issue 1 remains the full CV32E40P path. Issue 2 is opportunistic and is added
incrementally. A failure to issue instruction 2 must never prevent instruction 1
from making forward progress.

## Current implementation status

Implemented as isolated, synthesizable building blocks:

- `cv32e40p_dual_issue_idu.sv`: partial decode, Issue2 eligibility, RAW/WAW checks,
  and conservative serialization.
- `cv32e40p_issue2_decoder.sv`: restricted RV32I OP/OP-IMM decoder for Issue2.
- `cv32e40p_issue2_ex.sv`: scalar secondary ALU lane with one-entry writeback
  buffering and kill support.
- `cv32e40p_issue2_lane.sv`: composed Issue2 decoder + execution lane.
- `cv32e40p_register_file_5r3w.sv`: experimental 5-read/3-write FF register file.
- Directed unit tests for the IDU and Issue2 lane.

The baseline core pipeline has deliberately not yet been rewired. This keeps the
master CV32E40P behavior intact while the new blocks are stabilized. The next
integration step is to expose instruction 2 and its operands to the ID stage,
then connect Issue2 writeback through the 5R3W register-file experiment.

## Milestones

1. **IDU / partial decode — implemented**
   - Identify Issue2-safe RV32 integer ALU instructions.
   - Detect same-cycle Issue1 -> Issue2 RAW hazards.
   - Detect WAW conflicts.
   - Serialize branches/jumps/system/fence operations until speculation exists.
   - Keep memory operations on Issue1 only.

2. **Two-instruction frontend prototype — next integration target**
   - Start with fixed-width 32-bit instructions (PC and PC+4).
   - Expose instruction-2 valid/data/PC to ID.
   - Keep compressed-instruction dual fetch disabled initially.

3. **Secondary decode and ALU execution lane — block implementation complete**
   - Restricted RV32I OP/OP-IMM decode is implemented.
   - Scalar Issue2 ALU path is implemented using the existing CV32E40P ALU.
   - One-entry Issue2 writeback state and kill input are implemented.
   - Core-level wiring remains pending.

4. **Register-file / writeback extension — experimental block implemented**
   - A straightforward 5R3W flip-flop register file is available for PPA study.
   - W3 > W2 > W1 deterministic write priority is used; IDU WAW filtering should
     make normal dual-issue W3/W1 collisions impossible.
   - Integration into `cv32e40p_id_stage` remains pending.
   - Lower-cost alternatives should be evaluated against this baseline.

5. **Cross forwarding and pipeline hazards**
   - EX1 -> Issue2, EX2 -> Issue1, EX2 -> Issue2, and WB forwarding as needed.
   - Verify load-use, multi-cycle and stall interactions.

6. **Branch speculation / kill**
   - Permit a safe Issue2 instruction behind a conditional Issue1 branch.
   - Kill Issue2 architectural writeback when the branch redirects execution.
   - The Issue2 execution block already exposes `kill_i` for this purpose.

7. **Xpulp / DSP / AI-oriented secondary execution**
   - Add selected SIMD/DSP operations based on area/performance benefit.
   - Keep three-source and memory-heavy operations restricted until explicitly supported.

8. **RV32C-aware dual fetch and L0 frontend**
   - Identify two variable-width instructions across fetch boundaries.
   - Add wider fetch / small L0 instruction storage and prefetch policy.

## Current pairing policy

Allowed examples:

- ALU -> independent ALU
- ALU -> independent OP-IMM
- load/store on Issue1 -> independent ALU on Issue2

Blocked examples:

- Issue1 rd == Issue2 rs1/rs2 (RAW)
- Issue1 rd == Issue2 rd (WAW)
- memory operation on Issue2
- MUL/DIV on Issue2
- branch/jump/system/fence on Issue1
- unsupported/custom operation on Issue2

## Verification principle

At every milestone, single-issue execution remains the golden fallback. Directed
pairing tests are added before enabling a new instruction class. Full core
regression and RISC-V compliance testing are required before claiming integrated
milestones complete.
