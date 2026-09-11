# CV32E40P asymmetric dual-issue development

This branch develops a HAMSA-DI-inspired asymmetric dual-issue extension while
preserving CV32E40P single-issue behavior as the architectural reference.

## Design rule

Issue 1 remains the full CV32E40P path. Issue 2 is opportunistic and is added
incrementally. A failure to issue instruction 2 must never prevent instruction 1
from making forward progress.

## Milestones

1. **IDU / partial decode (current)**
   - Identify Issue2-safe RV32 integer ALU instructions.
   - Detect same-cycle Issue1 -> Issue2 RAW hazards.
   - Detect WAW conflicts.
   - Serialize branches/jumps/system/fence operations until speculation exists.
   - Keep memory operations on Issue1 only.

2. **Two-instruction frontend prototype**
   - Start with fixed-width 32-bit instructions (PC and PC+4).
   - Expose instruction-2 valid/data/PC to ID.
   - Keep compressed-instruction dual fetch disabled initially.

3. **Secondary decode and ALU execution lane**
   - Add Issue2 operand/control generation.
   - Instantiate a restricted secondary integer ALU path.
   - Add Issue2 ID/EX state and writeback validity.

4. **Register-file / writeback extension**
   - Evaluate straightforward 5R3W RF versus lower-cost alternatives.
   - Add third architectural write path or an equivalent conflict-free scheme.
   - Preserve x0 behavior and deterministic same-cycle write priority.

5. **Cross forwarding and pipeline hazards**
   - EX1 -> Issue2, EX2 -> Issue1, EX2 -> Issue2, and WB forwarding as needed.
   - Verify load-use, multi-cycle and stall interactions.

6. **Branch speculation / kill**
   - Permit a safe Issue2 instruction behind a conditional Issue1 branch.
   - Kill Issue2 architectural writeback when the branch redirects execution.

7. **Xpulp / DSP / AI-oriented secondary execution**
   - Add selected SIMD/DSP operations based on area/performance benefit.
   - Keep three-source and memory-heavy operations restricted until explicitly supported.

8. **RV32C-aware dual fetch and L0 frontend**
   - Identify two variable-width instructions across fetch boundaries.
   - Add wider fetch / small L0 instruction storage and prefetch policy.

## Current Milestone-1 pairing policy

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
regression and RISC-V compliance testing are required before claiming a milestone
is complete.
