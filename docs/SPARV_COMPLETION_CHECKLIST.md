# SPARV completion checklist

This branch builds SPARV on the verified HAMSA-DI/H2 foundation. “Implemented”
means the repository contains synthesizable RTL plus a reproducible generation or
test path. “Measured” is reserved for results actually produced by a simulator,
FPGA flow, or ASIC backend; this document does not invent paper-reproduction
numbers.

## RTL / integration

- [x] HAMSA-DI asymmetric dual-issue backend and recovery foundation.
- [x] 8-line x 128-bit L0 and RV32C-aware two-instruction extraction.
- [x] Legacy 4x32-bit and native 128-bit refill modes.
- [x] Next-line SPARV prefetch controller with demand priority.
- [x] Prefetch-residency/useful/wasted tracking and counters.
- [x] Redirect/FENCE.I handling without architecturally consuming speculative data.
- [x] Existing Xpulp `MUL_MAC32`, `MUL_DOT8`, and non-complex `MUL_DOT16`
      micro-operations routed to the SPARV multicycle datapath.
- [x] Baseline CV32E40P multiplier retained for MUL/MULH/rounded/MSU/complex
      compatibility cases.
- [x] 4xINT8, 2xINT16, and 1xINT32 arithmetic modes.
- [x] EX-stage backpressure and result hold behavior.
- [x] Generated full core (`cv32e40p_core_sparv`) and manifest.
- [x] Executable SPARV-32/SPARV-128 example-testbench generator.

## Verification infrastructure

- [x] Unit tests: prefetch controller, directory, refill arbiter.
- [x] Unit tests: arithmetic reference and multicycle engine.
- [x] Integrated multiplier test including backpressure, consecutive accelerated
      operations and baseline fallback.
- [x] Full-core Verilator lint in GitHub Actions.
- [x] SPARV-32/SPARV-128 generation smoke tests in GitHub Actions.
- [x] Runtime metric emission for dual issue, L0, prefetch, TCIM requests and
      MAC/DOTP modes.
- [ ] Full architectural program regression is **measured green** on a supported
      RTL simulator. The scripts are present, but this box is checked only after
      actual firmware runs complete successfully.
- [ ] CORE-V/RISC-V compliance suite is **measured green** on SPARV.
- [ ] Interrupt/debug/WFI/FENCE/fault stress suite is **measured green** on SPARV.

## Evaluation infrastructure

- [x] B0/HAMSA/SPARV executable configuration selection.
- [x] SPARV log parser and CSV schema.
- [x] PPA matrix supports B0, HAMSA, SPARV-32 and SPARV-128 using one identical
      external backend command.
- [x] Methodology covers CoreMark, Embench, AES, DOTP, TCIM traffic, prefetch
      accuracy/coverage, IPC, area, frequency, power and energy.
- [ ] CoreMark/Embench/AES/DOTP numbers are **measured**. Requires compiled
      firmware and a simulator/toolchain; no result is fabricated in this repo.
- [ ] FPGA utilization/Fmax/power are **measured** on a named device/flow.
- [ ] ASIC area/Fmax/power/energy are **measured** with a named cell library,
      PVT corner and synthesis/P&R flow.

## Reproduction boundary

The public SPARV description does not disclose the exact CORDIC micro-rotation
schedule/netlist for the combined Mult/Div/MAC/DOTP unit. The implementation in
this branch reproduces the documented operation classes, SIMD widths and
multicycle execution contract behind a replaceable arithmetic kernel. It must
not be described as a bit-for-bit reproduction of unpublished CORDIC internals.
If the original microarchitecture becomes available, replace the kernel behind
`cv32e40p_sparv_mac_dotp_engine` while keeping the verified decode, handshake,
frontend and evaluation infrastructure unchanged.

## One-command entry points

Executable simulation (given a valid program hex):

```bash
python3 evaluation/run_example_vsim.py SPARV-32  program.hex
python3 evaluation/run_example_vsim.py SPARV-128 program.hex
```

Identical-backend PPA matrix:

```bash
python3 evaluation/run_ppa_matrix.py \
  --configs B0,H2-32,H2-128,SPARV-32,SPARV-128 \
  --command 'my_flow --manifest {manifest} --top {top} --out {outdir} {params}'
```

Only measured outputs from those flows should be reported as evaluation results.
