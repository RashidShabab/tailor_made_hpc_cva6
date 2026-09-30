# Phase-1 SBTMH Classification Policy

## Scope

This document freezes the classification semantics for the first CVA6 TMH
evaluation baseline.  It describes the implementation at upstream CVA6
revision `81245a47fad8fe1a5d562d953ef2662e099def76`, configuration
`cv64a6_imafdc_sv39`, with Zcmp disabled.

The monitor classifies **only successfully retired entries**: a commit event
is `commit_ack[p]`, where `commit_ack` in `core/cva6.sv` has already excluded
dropped scoreboard entries and Zcmp macro intermediates.  Port order is
ascending (`0`, then `1`), from oldest to youngest.

## Alphabet and precedence

Classification uses CVA6's decoded `scoreboard_entry_t.fu` and, for ALU
Boolean operations, `scoreboard_entry_t.op`.  It intentionally does not
re-decode an instruction word.

| Class | Exact phase-1 rule | Examples / consequence |
| --- | --- | --- |
| `B` | `fu == CTRL_FLOW` | conditional branches, `JAL`, `JALR` |
| `L` | `fu == LOAD` | integer, hypervisor, and FP loads |
| `S` | `fu == STORE` | integer, hypervisor, and FP stores; all AMOs |
| `N` | `fu == ALU` and `op` is `XORL`, `ORL`, or `ANDL` | integer Boolean operations only |
| `A` | `fu == ALU` other than the three `N` operations, or `fu == MULT` | adds, shifts, comparisons, multiply/divide, and supported ALU extensions |
| `X` | every other functional unit | CSR/system/fence, FP/vector computation, accelerator/custom paths, AES, and unsupported paths |

The table is ordered.  In particular, the `N` predicate is checked before
the general `A` case.  `X` is not a sixth counted alphabet symbol: it clears
the retained predecessor, so no pair bridges across an `X` instruction.

## Rationale and boundaries

This policy follows the existing CVA6 decoded functional-unit allocation and
keeps the first experiment stable and inexpensive.  It is a measurement
definition, not a claim that an AMO is semantically identical to a simple
store or that FP memory instructions are interchangeable with integer memory
instructions.  Those choices must be reported with every dataset.

`CSR`, `FENCE`, `ECALL`, `MRET`, and similar system activity intentionally
break history.  This prevents unrelated B/L/S/A/N instructions on opposite
sides of a system boundary from being counted as architecturally adjacent in
the phase-1 alphabet.

Zcmp is outside this policy.  The integration asserts that Zcmp is disabled;
no dataset may enable it until macro-instruction retirement semantics are
specified and verified.

## Required verification additions

Before general-workload results are used, extend the directed full-core test
with retirement-visible examples for:

1. an FP load and store, verifying `L` and `S` respectively;
2. LR/SC and a read-modify-write AMO, verifying their current `S` treatment;
3. a fence and a CSR/system instruction, verifying `X` clears history;
4. a representative Zbb/extension ALU operation, verifying `A` unless it is
   explicitly one of `XORL`, `ORL`, or `ANDL`;
5. FP arithmetic, verifying `X` clears history.

Any change to a row above is a new measurement version: bump the software
trace metadata and rerun the complete directed regression.
