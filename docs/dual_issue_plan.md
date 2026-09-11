# CV32E40P asymmetric dual-issue development

This branch implements a HAMSA-DI-inspired asymmetric dual-issue extension while
preserving the original CV32E40P implementation on `CV32e40p-original` as the
architectural reference.

## Architectural rule

Issue 1 remains the full CV32E40P pipeline. Issue 2 is younger and opportunistic.
Failure to issue instruction 2 must never stall or corrupt instruction 1. Issue 2
may execute speculatively, but it cannot become architecturally visible until the
older primary instruction is commit-safe.

## Implemented RTL

### Issue / execution

- `cv32e40p_dual_issue_idu.sv`
  - partial decode for pairing decisions;
  - same-cycle RAW and WAW checks;
  - conservative serialization of unknown/custom Issue1 classes;
  - optional speculation behind conditional branches;
  - Issue2 support for scalar RV32I OP/OP-IMM and scalar RV32M MUL.
- `cv32e40p_issue2_decoder.sv`
  - restricted Issue2 decoder;
  - integer ALU operations plus MUL;
  - DIV/REM/MULH-family, memory, CSR, jumps and custom operations remain excluded.
- `cv32e40p_issue2_ex.sv` / `cv32e40p_issue2_lane.sv`
  - secondary scalar ALU/MUL execution;
  - one-entry result buffer;
  - kill support for branch/exception/debug recovery;
  - backpressure until a safe writeback opportunity exists.
- `cv32e40p_dual_issue_forwarding.sv`
  - EX1/EX2/WB1/WB2 forwarding helper.
- `cv32e40p_dual_issue_recovery.sv`
  - kills younger Issue2 state on a taken primary branch or other redirect.

### Register file / writeback

- `cv32e40p_register_file_5r3w.sv`
  - experimental 5-read/3-write flip-flop RF for PPA comparison.
- `cv32e40p_dual_issue_pair_unit.sv`
  - standalone 5R3W integration scaffold.
- `cv32e40p_dual_issue_integration_bridge.sv`
  - conservative sidecar integration using a mirrored integer RF.
- `cv32e40p_hamsa_issue_cluster.sv`
  - current primary/secondary integration block;
  - mirrored architectural integer state for Issue2 operand reads;
  - cross-lane forwarding;
  - primary write-port priority;
  - Issue2 result is held until `primary_commit_safe_i` is asserted, preserving
    in-order architectural visibility for older loads/stores/faulting operations.

### Frontend

- `cv32e40p_dual_fetch_pair_buffer.sv`
  - lossless pair assembly for the existing 32-bit frontend;
  - if Issue2 is rejected, instruction 2 is replayed as the next Issue1.
- `cv32e40p_l0_icache_128.sv`
  - 8-line x 128-bit direct-mapped L0 prototype.
- `cv32e40p_dual_decode_128.sv`
  - RV32C-aware extraction/decompression of up to two sequential instructions
    from a 128-bit cache line.
- `cv32e40p_hamsa_frontend.sv`
  - integrated 128-bit L0 + RV32C dual-decode frontend with redirect support.
- `cv32e40p_hamsa_dual_issue_top.sv`
  - integration adapter combining the 128-bit frontend, recovery logic and
    secondary issue cluster around an external/full-featured primary lane.

### Core integration path

`util/gen_hamsa_core.py` deterministically generates
`rtl/cv32e40p_core_hamsa.sv` from the untouched `rtl/cv32e40p_core.sv`.
It performs checked substitutions and fails if an expected source anchor changes.
The generated bring-up core currently uses the original 32-bit fetch interface
plus the lossless pair buffer, and connects the secondary issue cluster at the
ID/EX/RF boundary. This avoids maintaining a large divergent fork while the
integration is validated.

The separate `cv32e40p_hamsa_frontend.sv` / `cv32e40p_hamsa_dual_issue_top.sv`
path represents the final 128-bit-L0 organization and requires a widened refill
or instruction-cache interface at SoC integration level.

## Pairing policy

Currently allowed on Issue2:

- ADD/SUB, shifts, compares and logical RV32I OP instructions;
- OP-IMM arithmetic/logical/shift instructions;
- scalar RV32M MUL;
- an independent Issue2 ALU/MUL may pair behind an Issue1 load/store;
- an independent Issue2 instruction may be issued speculatively behind an
  Issue1 conditional branch in `cv32e40p_hamsa_issue_cluster`.

Currently excluded on Issue2:

- loads/stores;
- branches/jumps;
- CSR/system/fence instructions;
- DIV/REM and MULH-family operations;
- Xpulp custom/SIMD/DSP instructions not yet explicitly decoded;
- three-source operations.

RAW and WAW conflicts always block Issue2. Unknown/custom Issue1 instruction
classes serialize conservatively.

## Ordering and recovery

A younger Issue2 result is buffered after execution and is released only when
`primary_commit_safe_i` indicates the older Issue1 instruction has completed
without a fault. A primary ALU write has priority over the Issue2 write port.
Taken branches and other redirects kill any buffered younger result before it can
retire. This allows branch speculation without violating in-order architectural
state.

## Verification assets

Directed tests currently include:

- IDU legality / RAW / WAW / MUL / conservative serialization;
- Issue2 ALU and MUL execution plus kill behavior;
- pair-buffer replay and metadata preservation;
- 128-bit frontend extraction and redirect behavior;
- issue-cluster commit gating, RAW blocking, speculative branch issue and kill;
- standalone pair-unit integration.

`.github/workflows/hamsa-dual-issue.yml` contains Icarus-based smoke tests and
also runs `util/gen_hamsa_core.py` to ensure the generated-core integration
anchors remain valid.

**Important:** presence of the tests and workflow is not equivalent to a passing
full-core regression. The branch should not be called production-verified until
CI/toolchain execution has actually completed, the generated core elaborates in
the project-supported simulator, and architectural regressions pass.

## Performance instrumentation

`cv32e40p_hamsa_perf_counters.sv` provides non-architectural 64-bit counters for:

- cycles;
- Issue1 retired instructions;
- Issue2 issued / retired / blocked / killed instructions;
- L0 lookups and hits.

These are kept separate from the privileged CSR map so performance studies can
be performed without changing software-visible architecture during bring-up.

## Remaining validation / research tasks

1. Run full project-supported compile/elaboration for `cv32e40p_core_hamsa`.
2. Run CV32E40P regression and RISC-V architectural/compliance tests with dual
   issue disabled/enabled and compare architectural state.
3. Stress load-use, stores, LSU errors, interrupts, debug entry, FENCE.I, WFI,
   APU/FPU and multicycle interactions.
4. Integrate the 128-bit L0 refill path with the selected SoC instruction-memory
   protocol and test cross-line RV32C/32-bit instruction cases.
5. Compare the native 5R3W RF against the mirrored-RF bring-up implementation for
   area, timing and energy; select the final physical implementation.
6. Add selected Xpulp/SIMD/DSP operations only after their dependency semantics
   are represented in the partial decoder.
7. Run CoreMark/Embench and collect IPC, pair rate, Issue2-block reasons, L0 hit
   rate, area, Fmax and energy versus `CV32e40p-original`.
8. FPGA and/or ASIC synthesis and timing closure before claiming PPA results.

## Suggested bring-up commands

```sh
python3 util/gen_hamsa_core.py
# then compile the generated rtl/cv32e40p_core_hamsa.sv with the normal project
# package/include/source set plus the HAMSA RTL listed in Bender.yml.
```

The preserved reference branch remains `CV32e40p-original`; HAMSA development
stays isolated on `feature/hamsa-dual-issue`.
