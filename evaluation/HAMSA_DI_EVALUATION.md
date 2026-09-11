# HAMSA-DI Evaluation Setup

This directory defines a reproducible evaluation methodology for the asymmetric
dual-issue CV32E40P development branch. All comparisons should use
`CV32e40p-original` as the single-issue baseline and
`feature/hamsa-dual-issue` as the modified design.

## 1. Evaluation questions

The evaluation should answer four independent questions:

1. **Correctness:** does dual issue preserve architectural state relative to the
   baseline for the same program?
2. **Performance:** how much do IPC, execution cycles and benchmark score improve?
3. **Microarchitectural efficiency:** how often is Issue2 useful, blocked or killed,
   and what limits pairing?
4. **Cost:** what are the area, Fmax, power and energy overheads of the dual-issue
   frontend, secondary lane and register-file organization?

Do not mix functional validation with PPA claims. PPA numbers are meaningful only
for a configuration that has already passed architectural regression.

## 2. Configurations

Evaluate at least these configurations using identical compiler flags and memory
system assumptions.

| ID | Core | Dual issue | L0 | Purpose |
|---|---|---:|---:|---|
| B0 | `CV32e40p-original` | off | baseline | golden reference |
| H0 | HAMSA core | off | off | integration-equivalence check |
| H1 | HAMSA core | on | off | backend dual-issue benefit |
| H2 | HAMSA core | on | on | full frontend + backend benefit |

For PPA, also synthesize the two register-file choices separately when available:
mirrored-RF bring-up and native 5R3W RF.

## 3. Functional validation

Before benchmarks, run:

- HAMSA directed CI smoke tests;
- CV32E40P project regression;
- RISC-V architectural/compliance tests supported by the project;
- randomized ALU dependency tests;
- load-use and store ordering tests;
- taken/not-taken branch tests with speculative Issue2;
- interrupt, exception, debug-entry and redirect tests;
- compressed-instruction boundary tests;
- FENCE.I/WFI/APU/FPU interactions for enabled configurations.

For B0 versus H0, compare architectural register and memory signatures. They should
match exactly for the same binary.

## 4. Performance workloads

### Primary paper-facing workloads

Use:

- CoreMark;
- Embench-IoT;
- selected CV32E40P/PULP DSP kernels if the software environment already supports
  them.

For CoreMark report both raw score and CoreMark/MHz. For Embench report the suite
aggregate and per-benchmark normalized score.

### Microbenchmarks

Add short kernels that isolate pairing opportunities:

- independent ALU + ALU;
- dependent ALU chains;
- load + independent ALU;
- store + independent ALU;
- branch + independent ALU, taken and not taken;
- MUL + independent ALU;
- intentionally unsupported Issue2 opcodes.

These are required to interpret benchmark-level results.

## 5. Runtime metrics

The branch contains `cv32e40p_hamsa_perf_counters.sv` and the combined
`cv32e40p_hamsa_eval_monitor.sv`. Capture at least:

- cycles;
- Issue1 retired instructions;
- Issue2 issued instructions;
- Issue2 retired instructions;
- Issue2 blocked instructions;
- Issue2 killed instructions;
- L0 lookups;
- L0 hits.

Derive:

- total retired instructions = issue1_retired + issue2_retired;
- IPC = total retired / cycles;
- Issue2 issue rate = issue2_issued / cycles;
- Issue2 retirement rate = issue2_retired / cycles;
- pair utilization = issue2_retired / total retired;
- block rate = issue2_blocked / (issue2_issued + issue2_blocked);
- kill rate = issue2_killed / issue2_issued;
- L0 hit rate = l0_hits / l0_lookups.

For benchmark comparisons also compute:

- speedup = baseline_cycles / hamsa_cycles;
- cycle reduction (%) = 100 * (baseline_cycles - hamsa_cycles) / baseline_cycles.

## 6. Block-reason instrumentation

The branch exposes the following Issue2 block causes:

- RAW;
- WAW;
- unsupported Issue2 instruction;
- serializing Issue1 instruction;
- Issue2 execution/result-buffer busy;
- secondary decode rejection.

These reason signals are intentionally **non-exclusive** in the current prototype.
For example, one candidate may be both RAW-dependent and unsupported. Therefore the
sum of reason counters may exceed `issue2_blocked`. For stacked figures either use
an explicit priority classification in post-processing or label the figure as
"fraction of blocked opportunities exhibiting each cause" rather than forcing the
categories to sum to 100%.

Future instrumentation should additionally separate primary writeback conflict,
redirect/flush/debug/exception, and frontend starvation/no-second-instruction when
those signals are available at the chosen integration boundary.

## 7. Simulator log contract

Benchmark testbenches should print one or more lines beginning with `HAMSA_METRIC`
and containing whitespace-separated `key=value` tokens. Example:

```text
HAMSA_METRIC cycles=123456 issue1_retired=100000 issue2_issued=23500
HAMSA_METRIC issue2_retired=23000 issue2_blocked=15100 issue2_killed=12
HAMSA_METRIC block_raw=8000 block_waw=40 block_unsupported=4200
HAMSA_METRIC block_serializing=2800 block_busy=900 block_decode=0
HAMSA_METRIC l0_lookups=40000 l0_hits=38600 benchmark_score=3.42
```

`evaluation/parse_hamsa_log.py` converts one simulator log into a canonical CSV
row. `evaluation/run_benchmark_matrix.py` runs a complete B0/H0/H1/H2 matrix using
any simulator command template that emits the same log contract.

Example:

```bash
python3 evaluation/run_benchmark_matrix.py \
  --benchmarks coremark,aha-mont64 \
  --configs B0,H0,H1,H2 \
  --command './run_sim.sh {configuration} {benchmark}' \
  --out evaluation/results/raw.csv

python3 evaluation/compute_metrics.py \
  evaluation/results/raw.csv \
  --output evaluation/results/derived.csv
```

The runner stores individual logs in `evaluation/results/logs/` by default and
records the current git SHA automatically.

## 8. FPGA evaluation

Use the same target device, constraints and memory wrapper for B0 and HAMSA.
Report:

- LUTs/ALMs;
- flip-flops/registers;
- BRAM/M20K blocks;
- DSP blocks;
- post-route Fmax;
- benchmark cycles;
- board power if the measurement setup is repeatable.

Do not compare synthesis-only Fmax for one design against post-route Fmax for the
other.

## 9. ASIC evaluation

For both designs use identical:

- technology/library;
- PVT corner;
- voltage;
- target clock;
- synthesis/place-and-route flow;
- utilization target;
- SRAM assumptions;
- switching-activity methodology.

Report total area, cell area, sequential/combinational area, worst slack/Fmax,
dynamic power, leakage power and energy per benchmark.

For energy:

`energy = average_power * execution_time`

where execution time is derived from measured benchmark cycles and the achieved or
fixed comparison frequency.

## 10. Required ablations

At minimum evaluate:

1. baseline single issue;
2. dual issue without L0;
3. dual issue with L0;
4. speculation disabled versus enabled;
5. Issue2 ALU-only versus ALU+MUL;
6. mirrored RF versus native 5R3W RF for PPA.

These distinguish where performance and hardware cost come from.

## 11. Recommended result tables/figures

Prepare:

- benchmark speedup bar chart;
- IPC and Issue2 pair-utilization chart;
- Issue2 block-reason chart;
- L0 hit-rate chart;
- area breakdown;
- power/energy comparison;
- performance-versus-area and performance-versus-energy scatter plots;
- ablation table.

## 12. Reproducibility rules

Record for every result:

- git commit SHA;
- branch/configuration;
- simulator or synthesis tool version;
- compiler version and exact flags;
- benchmark commit/version;
- clock period/frequency;
- memory latency configuration;
- number of runs and aggregation method.

Never combine numbers produced from different compiler flags or memory settings in
one direct comparison.

## 13. Result collection

Use `evaluation/results_template.csv` as the canonical raw-results schema and
`evaluation/compute_metrics.py` to derive IPC, utilization, hit rate and speedup.
Keep raw tool reports separately; the CSV should contain only extracted values,
not hand-normalized presentation numbers.
