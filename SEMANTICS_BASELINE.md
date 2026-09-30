# SBTMH Experiment 0/1 Semantics Baseline

## Status and scope

This is the **provisional but fixed-for-comparability** baseline for
Experiment 0 and Experiment 1. It applies to CVA6
`81245a47fad8fe1a5d562d953ef2662e099def76`, configuration
`cv64a6_imafdc_sv39`, with `TmhEn=1` and Zcmp disabled. A later semantic
change requires a new trace-metadata version and cannot be mixed with these
datasets.

## Simulator baseline

The baseline simulator is **Verilator 5.032 (Debian 5.032-1)** under WSL
Ubuntu. Full-core scenarios 0--4, the retained scenario-4 trace, and the
independent Exp 0 replay were produced or checked with this version. Verilator
5.008 is not an equivalent validated baseline; it may be evaluated later as a
compatibility result, but it must not silently replace 5.032 for Exp 1.

## Classification

The counted alphabet is `B/L/S/A/N`; `N` means Boolean/logical, not
"None." The complete raw-CVA6 functional-unit policy is in
[CLASSIFICATION_POLICY.md](CLASSIFICATION_POLICY.md): AMOs are `S`, FP loads
and stores are `L`/`S`, and non-Boolean ALU operations including shifts,
comparisons, LUI/AUIPC, multiply, and divide are `A`. Unsupported/system,
fence, CSR, FP/vector-compute, and custom paths are `X`, which is uncounted
and clears history.

## Trap and interrupt policy

The implemented event generator has no trap or interrupt input and therefore
does **not** explicitly clear history on a trap or interrupt boundary. The
last successfully observed `B/L/S/A/N` class remains the predecessor. The
first subsequently acknowledged class instruction, including one in a trap
handler, can form a pair with it. `X` instructions encountered through the
ordinary retirement interface still clear history by the classification rule.

This behavior is intentional only as the current baseline, not as a final
architectural claim. Experiment 1's bare-metal Spectre-v1 program is expected
not to trap, so it is unaffected. Trap and interrupt directed tests are still
required before making claims about workloads that use those boundaries.

## Exp 0 evidence

Run the independent replay:

```bash
python3 verification/golden_model.py \
  sim/build/cva6_integration_enabled/scenario_4/trace_hart_0.dasm
```

The retained 2026-09-23 scenario-4 trace passes: all 25 selected `B/L/S/A/N`
pair snapshots equal one. See [verification/EXP0_EVIDENCE.md](verification/EXP0_EVIDENCE.md).
