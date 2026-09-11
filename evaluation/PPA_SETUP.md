# HAMSA-DI PPA evaluation protocol

Use one tool/version, one technology/FPGA device, one clock constraint and one
memory treatment for every configuration. Do not compare numbers produced by
different flows.

## Configurations

- B0: original CV32E40P
- H0: HAMSA integration, Issue2 disabled
- H1: HAMSA backend dual issue enabled
- H2-32: H1 + 8x128-bit L0/RV32C frontend + four-beat 32-bit refill
- H2-128: H2 frontend + native 128-bit line refill

## FPGA

Record LUT/ALM, FF, BRAM, DSP, Fmax, total cycles and benchmark score. Use the
same seed/effort level where the vendor tool permits. For noisy place-and-route
results, report at least three seeds and retain the raw reports.

## ASIC

Recommended flow:

1. elaborate identical parameter sets,
2. synthesize to the same standard-cell library,
3. apply the same clock/IO uncertainty and wire-load/RC assumptions,
4. place and route with the same density and optimization effort,
5. run STA at the same PVT corner,
6. estimate dynamic power using the same activity methodology,
7. report leakage separately.

Collect:

- combinational area
- sequential area
- memory/macro area
- total cell/core area
- worst slack and Fmax
- dynamic power
- leakage power
- energy per retired instruction
- performance/area

## Register-file ablation

The bring-up design mirrors architectural state for the secondary lane. The
native `cv32e40p_register_file_5r3w.sv` experiment should be synthesized as a
separate ablation because RF area/timing is expected to be a major dual-issue
cost. Compare:

1. B0 3R2W RF
2. H1 mirrored/shadow RF bring-up
3. H1 native 5R3W RF

## Energy

For a benchmark with average power P and runtime cycles C at frequency f:

`energy = P * C / f`

and

`energy_per_instruction = energy / retired_instructions`.

Report both absolute energy and baseline-normalized energy.

## Reproducibility metadata

Every CSV row should include git SHA, tool version, compiler version/flags,
clock target, memory configuration and a short notes field. Keep raw synthesis,
STA and power reports under a separate results directory rather than copying
only headline numbers into a paper table.
