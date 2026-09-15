# SPARV evaluation setup

This directory extends the HAMSA-DI evaluation flow for the SPARV branch.
The goal is to measure the architectural effects that are actually implemented
in this repository and keep paper targets separate from measured results.

## Configurations

Evaluate at least the following four builds with the same compiler, benchmark
binary, memory model and timing assumptions:

1. `CV32E40P-original` — baseline CV32E40P.
2. `feature/hamsa-dual-issue` — HAMSA-DI H2 foundation.
3. `feature/sparv` with prefetch disabled — isolates accelerated execution.
4. `feature/sparv` full — prefetch + HAMSA-DI + SPARV execution datapath.

For ablation, additionally compare native 128-bit refill and 4x32-bit refill.

## Functional regression

Run the SPARV GitHub Actions workflow first. It covers:

- next-line prefetch controller and prefetch metadata,
- demand-priority refill arbitration,
- 4x8 / 2x16 / 1x32 MAC-DOTP arithmetic,
- multicycle execution latency/handshake,
- integrated `cv32e40p_sparv_mult` compatibility,
- generated SPARV IF + EX integration,
- full-core Verilator lint.

The generated full core must contain both `cv32e40p_sparv_if_stage` and
`cv32e40p_sparv_ex_stage`. The latter replaces only the multiplier instance
with `cv32e40p_sparv_mult`, preserving the standard CV32E40P EX-stage contract.

## Performance workloads

Primary benchmarks should mirror the SPARV paper where possible:

- CoreMark, reported as CM/MHz and total cycles;
- Embench, reported with the standard geometric-mean score;
- Nettle-AES / AES microbenchmarks;
- INT8 and INT16 dot-product kernels;
- scalar MAC and RV32M multiply/divide microbenchmarks;
- branch/control and memory-heavy kernels to expose prefetch side effects.

Do not enter the paper's published speedups into measured CSV rows. Use them
only as external reference targets.

## Required counters

Collect the existing HAMSA counters plus SPARV-specific signals:

- cycles and retired instructions;
- dual-issued instruction pairs and dual-issue utilization;
- L0 lookups, hits, misses and refills;
- prefetch candidates, issued requests, fills, useful fills, wasted fills and
  suppressed requests;
- demand misses;
- MAC/DOTP operations by precision mode;
- cycles stalled by the SPARV multicycle engine;
- TCIM instruction-memory requests.

Derived metrics:

- IPC = retired / cycles;
- dual-issue utilization = dual-issued pairs / cycles;
- L0 hit rate = hits / lookups;
- prefetch accuracy = useful / filled;
- prefetch coverage = useful / demand-miss opportunities;
- prefetch waste rate = wasted / filled;
- TCIM reduction versus baseline = 1 - requests_variant / requests_baseline;
- speedup = cycles_baseline / cycles_variant;
- energy improvement = 1 - energy_variant / energy_baseline.

## Synthesis/PPA

Use the existing `evaluation/PPA_SETUP.md` flow and synthesize the exact same
constraints for baseline, HAMSA-DI and SPARV. For reproducibility record:

- technology/library and PVT corner;
- target clock and achieved Fmax;
- total cell area and sequential/combinational area;
- total power, dynamic power and leakage;
- benchmark/activity source used for power estimation;
- memory macros or synthesized-memory assumptions.

The paper reports a 250 MHz 65 nm implementation and a 96.7 MHz 180 nm
implementation, but those are reference points, not repository results.

## Suggested result table

Use `sparv_results_template.csv` and one row per
`configuration x benchmark x refill_mode` combination.

The evaluation is considered complete only when functional CI is green and the
same benchmark binaries have been run across all compared configurations.
