# Experiment 0 — Full-Matrix Trace Cross-Check

## Question

Did scenario 4's expected counts come from an independent model rather than
from TMH RTL output or hand-calculated values?

## Finding

The original full-core testbench contains an independent SystemVerilog
scoreboard.  It decodes retired raw instruction bytes from AXI RAM, tracks
control CSR effects, and compares its expected counters against the TMH bank.
It does **not** derive expectations from `tmh_event_gen` outputs.  However,
there was no checked-in Python artifact for replaying the saved trace.

`golden_model.py` is the independent, runnable Exp 0 checker.  It consumes
`trace_hart_0.dasm`, emitted by the existing full-core scenario 4 run, rather
than monitor signals or counter state.  It uses a small raw RISC-V decoder for
the scenario's emitted instructions and treats everything else as `X`, the
history separator.  It models TMH control CSR writes and checks each selected
snapshot count.

Run from `cva6/`:

```bash
python3 verification/golden_model.py \
  sim/build/cva6_integration_enabled/scenario_4/trace_hart_0.dasm
```

Acceptance criterion: 25 selected low-counter snapshots are read, one per
ordered `B/L/S/A/N` pair, and every snapshot is exactly one.  The trace is a
retirement trace, so this check also validates the observed architectural
order, including its five dual-retirement cycles.

## Result

On the retained `scenario_4/trace_hart_0.dasm`, under WSL Ubuntu with Python
3 and Verilator 5.032 as the simulator baseline, the checker reported:

```text
PASS: 25 independent snapshot checks; all 25 B/L/S/A/N pairs equal 1
```

## Boundary

Python derives expected counts from retired instruction words; it does not
read hardware counter values or CSR return data. The SystemVerilog testbench
compares its expectations with live counters and both CSR counter halves.
Python alone does not prove hardware readout correctness or independently
validate the core retirement interface.

The researcher manually reran both standalone suites (35 named checks), all
five full-core scenarios, and this Python replay on Verilator 5.032. All
passed, as confirmed by the terminal output supplied in this task. These
checks do not replace trap/interrupt, overflow, or special-instruction tests.
