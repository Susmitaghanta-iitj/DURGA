# HAMSA-DI completion checklist

This document is the single source of truth for closing the prototype. It is
written to prevent partial blocks from being mistaken for a production-verified
core.

## Architecture already present

- asymmetric Issue1/Issue2 decision unit with RAW/WAW filtering
- restricted secondary RV32I ALU lane plus MUL support
- Issue2 writeback buffering and in-order commit gating
- cross-lane forwarding helper
- branch/exception/debug kill/recovery support
- sequential pair/replay frontend for backend bring-up
- 5R3W register-file experiment
- 8 x 128-bit L0 frontend with RV32C-aware dual extraction
- 32-bit-to-128-bit four-beat refill adapter
- performance and block-reason counters
- generated B0/H0/H1 simulation harnesses
- CSV collection, metric computation, directed microbench generation and plots

## Full-core configurations

| ID | Meaning | Status |
|---|---|---|
| B0 | untouched CV32E40P | executable |
| H0 | HAMSA integration, Issue2 off | executable |
| H1 | HAMSA Issue2 on, sequential 32-bit pair assembly | executable path present |
| H2-32 | 128-bit L0/RV32C frontend, four 32-bit refill beats | frontend/refill RTL present; full-core PC/control integration remains |
| H2-128 | same frontend with native 128-bit refill | interface architecture present; SoC/native bus integration remains |

## Mandatory correctness closure

1. Run all unit/smoke tests in `.github/workflows/hamsa-dual-issue.yml`.
2. Compile the generated full H1 core with the project-supported simulator.
3. Run the same RV32IMC binaries on B0/H0/H1 and compare architectural output.
4. Add directed tests for interrupt entry/return, debug entry/return, WFI, FENCE,
   load/store faults, misaligned accesses, branch-taken kill and compressed code.
5. Run RISC-V architectural/compliance tests supported by this repository.
6. Verify that H0 produces the same architectural state as B0.
7. Verify that H1 produces the same architectural state as B0 while allowing
   Issue2 retirement.

## H2 full-core integration (do not fake this by aliasing H1)

The remaining architectural work is to replace the generated sequential
pair-buffer path with `cv32e40p_hamsa_frontend` and give that frontend ownership
of instruction delivery while preserving the original CV32E40P redirect rules.
The hard requirement is PC/control equivalence: boot, jump, branch, trap, mret,
dret, hardware loop and debug redirects must all produce the same architectural
PC sequence as B0. The frontend already accepts redirect/invalidate and emits a
next-PC; the missing piece is the full-core PC/control bridge.

For H2-32, connect `cv32e40p_hamsa_refill_32to128` to the existing 32-bit
instruction memory interface. For H2-128, bypass that adapter and expose a native
128-bit line refill channel at the SoC boundary.

## Evaluation matrix

Use identical firmware images, compiler flags and memory timing for each row.
Primary comparisons:

- H0/B0: integration overhead
- H1/H0: backend dual-issue benefit
- H2-32/H1: L0 + dual-extraction benefit under unchanged external bandwidth
- H2-128/H2-32: benefit of native 128-bit refill bandwidth

Report cycles, total retired instructions, IPC, Issue2 issued/retired/blocked/
killed, block reasons, L0 lookups/hits, benchmark score, Fmax, area and power.

## Benchmark order

1. generated microbenchmarks (`python3 evaluation/gen_microbench.py`)
2. CoreMark
3. Embench
4. selected DSP/PULP kernels after secondary Xpulp coverage is extended

Run the executable matrix with:

```bash
python3 evaluation/run_full_matrix.py program.hex --name workload
```

Then generate plots with:

```bash
python3 evaluation/plot_results.py evaluation/results/full_matrix.csv
```

## PPA closure

Synthesize B0, H0, H1, H2-32 and H2-128 with the same library/device,
constraints and tool options. At minimum report:

- cell/LUT area
- FFs/registers
- memory/BRAM usage
- DSP usage where applicable
- worst-path Fmax
- dynamic and leakage power
- energy/instruction and performance/area

Compare the mirrored architectural-RF bring-up design against the native 5R3W
RF experiment because RF cost is expected to be a major dual-issue overhead.

## Definition of done

The branch is complete only when:

- CI is green,
- B0/H0/H1 full-core execution is regression-clean,
- H2-32 full-core execution uses the real 128-bit L0 frontend,
- H2-128 has a defined native line-refill SoC interface,
- architectural outputs match the baseline,
- benchmark CSVs are reproducible from one command,
- and PPA results are generated under identical constraints.
